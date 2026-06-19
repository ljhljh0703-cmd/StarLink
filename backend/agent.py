import asyncio
import logging
import sys
import json
import re

from dotenv import load_dotenv
from google.genai import types

from livekit.agents import Agent, AgentSession, AutoSubscribe, JobContext, WorkerOptions, cli, llm
from livekit.agents.voice.events import UserInputTranscribedEvent, SpeechCreatedEvent
from livekit.plugins import google
from livekit.plugins.google.realtime import RealtimeModel as _GoogleRealtimeModel

load_dotenv()

logger = logging.getLogger("starlink-agent")
logger.setLevel(logging.INFO)

# ──────────────────────────────────────────────
# System Instruction for Gemini Live Translate
# ──────────────────────────────────────────────
SYSTEM_INSTRUCTION = """\
You are a real-time simultaneous translator for a hearing aid user.

CRITICAL DIRECTIVES:
1. Target Output Language: Your output (both text and audio) MUST be KOREAN (한국어) ONLY. Never generate English, Japanese, Chinese, or any other non-Korean language under any circumstances.
2. Noise Isolation: If the input consists of ambient noise, background static, mumbling, coughing, or unclear speech, you MUST remain completely silent. Do not hallucinate or guess translations for noisy inputs.
3. Ignore Self-Feedback: Ignore any Korean audio. If your own translated voice leaks back into the microphone, remain absolutely silent. Ignore it completely.

Translation Rules:
1. Accurately translate any clear incoming English, Japanese, or Chinese speech into natural Korean speech immediately.
2. Do NOT output any ambient noise descriptions (e.g. "[music]", "[coughing]") — only output the translated Korean speech.
3. Preserve the speaker's original tone and intent in natural Korean.
4. Translate only clear and distinct statements. If a statement is cut off or unrecognizable, ignore it.
"""

# ──────────────────────────────────────────────
# System Instruction for Gemini Live Transcription (STT Only)
# ──────────────────────────────────────────────
TRANSCRIPTION_INSTRUCTION = """\
You are a real-time speech-to-text transcriber for a hearing aid user.

CRITICAL DIRECTIVES:
1. Transcription Only: Transcribe the user's speech exactly as heard in its original language (Korean, English, Japanese, Chinese, etc.).
2. No Translation: Do not translate the speech. Output the text in the original language spoken.
3. ABSOLUTE SILENCE: Do NOT generate any audio, voice, or speech output under any circumstances. You must remain completely silent. Do not speak.
4. DO NOT RESPOND: Do not reply to the user's speech. Do not generate any text response or conversation. Your sole purpose is to listen and let the ASR system transcribe.
5. Noise Isolation: If the input consists of ambient noise, background static, mumbling, coughing, or unclear speech, you must remain completely silent and not output any text.
"""

# ──────────────────────────────────────────────
# Helper for Language Detection
# ──────────────────────────────────────────────
def detect_language(text: str) -> str:
    if not text:
        return "unknown"
    
    text = text.strip()
    
    # Hangul (Korean)
    if any('\uac00' <= char <= '\ud7a3' or '\u1100' <= char <= '\u11ff' for char in text):
        return "ko"
        
    # Hiragana/Katakana (Japanese)
    if any('\u3040' <= char <= '\u309f' or '\u30a0' <= char <= '\u30ff' for char in text):
        return "ja"
        
    # Chinese characters (Hanzi)
    if any('\u4e00' <= char <= '\u9fff' for char in text):
        return "zh"
        
    # English/Latin
    latin_chars = sum(1 for char in text if ('a' <= char.lower() <= 'z'))
    if latin_chars > len(text) * 0.3:
        return "en"
        
    return "unknown"


# ──────────────────────────────────────────────
# Sentence Splitter Helper
# ──────────────────────────────────────────────
def extract_completed_sentences(text: str) -> tuple[list[str], str]:
    if not text:
        return [], ""
    # Split sentences by English and Asian sentence terminators (. ? ! 。 ？ ！）
    pattern = r'[^.?!。？！]+[.?!。？！]+'
    matches = re.findall(pattern, text)
    
    if not matches:
        return [], text
        
    matched_length = sum(len(m) for m in matches)
    remaining = text[matched_length:].strip()
    completed = [m.strip() for m in matches if m.strip()]
    return completed, remaining

# ──────────────────────────────────────────────
# Caption State Tracker (Pure Decision Logic)
# ──────────────────────────────────────────────
class CaptionStateTracker:
    def __init__(self):
        self.user_completed_sentences = []
        self.agent_completed_sentences = []
        self.current_user_text = ""
        self.current_agent_text = ""
        self.current_mode = "translation"
        self.agent_is_partial = True
        self.agent_transcript = ""

    def set_mode(self, mode: str):
        self.current_mode = mode

    def update_user_text(self, text: str):
        self.current_user_text = text

    def add_user_completed(self, completed: list[str]):
        self.user_completed_sentences.extend(completed)

    def update_agent_text(self, text: str):
        self.current_agent_text = text

    def set_agent_is_partial(self, is_partial: bool):
        self.agent_is_partial = is_partial

    def add_agent_completed(self, completed: list[str]):
        self.agent_completed_sentences.extend(completed)

    def handle_user_transcription(self, text: str, is_final: bool):
        """Updates user transcription state. Extracts completed sentences on final turn."""
        self.update_user_text(text)
        if is_final:
            completed, remaining = extract_completed_sentences(self.current_user_text)
            self.add_user_completed(completed)
            if remaining:
                self.add_user_completed([remaining])
            self.update_user_text("")

    def start_agent_turn(self):
        """Resets the agent state for a new translation turn."""
        self.set_agent_is_partial(True)
        self.agent_transcript = ""
        self.update_agent_text("")

    def handle_agent_chunk(self, text: str):
        """Appends and updates agent text chunk."""
        self.agent_transcript += text
        self.update_agent_text(self.agent_transcript.strip())

    def commit_agent_turn(self):
        """Commits final sentences of the current agent turn."""
        self.set_agent_is_partial(False)
        completed, remaining = extract_completed_sentences(self.current_agent_text)
        self.add_agent_completed(completed)
        if remaining:
            self.add_agent_completed([remaining])
        self.update_agent_text("")

    def get_segments(self) -> list[dict]:
        # Extract completed sentences from active buffers
        user_active_completed, user_active_remaining = extract_completed_sentences(self.current_user_text)
        agent_active_completed, agent_active_remaining = extract_completed_sentences(self.current_agent_text)
        
        # Build full sentence lists for alignment
        user_sentences = list(self.user_completed_sentences) + user_active_completed
        if user_active_remaining:
            user_sentences.append(user_active_remaining)
            
        agent_sentences = list(self.agent_completed_sentences) + agent_active_completed
        if agent_active_remaining:
            agent_sentences.append(agent_active_remaining)
            
        # Match sentences by index
        num_sentences = max(len(user_sentences), len(agent_sentences))
        segments = []
        
        for i in range(num_sentences):
            turn_id = f"turn-{i + 1}"
            orig = user_sentences[i] if i < len(user_sentences) else ""
            trans = agent_sentences[i] if i < len(agent_sentences) else ""
            
            # Determine isPartial
            if self.current_mode == "transcription":
                trans = orig
                is_partial = not (i < len(self.user_completed_sentences))
            else:
                is_partial = True
                if i < len(self.user_completed_sentences) and i < len(self.agent_completed_sentences):
                    is_partial = False
                else:
                    is_user_done = (i < len(user_sentences) - 1) or (i < len(user_sentences) and not user_active_remaining)
                    is_agent_done = (i < len(agent_sentences) - 1) or (i < len(agent_sentences) and not agent_active_remaining and not self.agent_is_partial)
                    if is_user_done and is_agent_done:
                        is_partial = False
                    
            segments.append({
                "id": turn_id,
                "original": orig,
                "translated": trans,
                "isPartial": is_partial,
                "language": detect_language(orig) if orig else "en"
            })
            
        # Trim historical segments in payload to avoid network bloat, client manages local retention
        if len(segments) > 100:
            segments = segments[-100:]
            
        return segments

# ──────────────────────────────────────────────
# Custom Realtime Model Wrapper to intercept session events
# ──────────────────────────────────────────────
class CustomRealtimeModel(_GoogleRealtimeModel):
    """
    Thin subclass of Google's RealtimeModel that surfaces two lifecycle hooks:

    • on_session_created(sess)  — fired right after session() creates the
      RealtimeSession.  Used here to monkeypatch generate_reply so the SDK
      never sends LiveClientContent/ActivityEnd packets to the streaming-only
      Gemini 3.5 Live Translate model.

    • on_generation_created(ev) — registered as the FIRST generation_created
      listener on the session, ensuring ev.message_stream is wrapped before
      AgentActivity consumes it (for caption interception & transcription-mode
      audio suppression).

    Both kwargs are stripped before forwarding to the parent __init__ so that
    RealtimeModel never sees unknown keyword arguments.
    """

    def __init__(self, *, on_session_created=None, on_generation_created=None, **kwargs):
        super().__init__(**kwargs)
        self._cb_session_created = on_session_created
        self._cb_generation_created = on_generation_created

    def session(self) -> llm.RealtimeSession:
        sess = super().session()
        # Register generation_created interceptor BEFORE AgentActivity does.
        # EventEmitter fires listeners in registration order, so wrapping
        # ev.message_stream here means AgentActivity sees the wrapped version.
        if self._cb_generation_created is not None:
            sess.on("generation_created", self._cb_generation_created)
        # Notify caller so it can monkeypatch generate_reply, attach close
        # listeners, etc.
        if self._cb_session_created is not None:
            self._cb_session_created(sess)
        return sess


async def entrypoint(ctx: JobContext):
    """Main agent entrypoint — connects Gemini 3.5 Live Translate to the LiveKit room."""
    logger.info("StarLink agent starting...")

    # Connect to the room and auto-subscribe to audio only
    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)
    logger.info(f"Connected to room: {ctx.room.name}")

    # Initialize state tracker for caption alignment (Pure Logic capsule)
    caption_tracker = CaptionStateTracker()
    session = None
    llm_session = None

    @ctx.room.on("data_received")
    def on_data_received(packet):
        try:
            payload = json.loads(packet.data.decode('utf-8'))
            if payload.get("type") == "mode_change":
                new_mode = payload.get("mode", "translation")
                if new_mode != caption_tracker.current_mode:
                    caption_tracker.set_mode(new_mode)
                    logger.info(f"App mode dynamically updated to: {caption_tracker.current_mode}")
                    # Dynamically switch Gemini's system instruction so the model
                    # actually honours transcription mode (no Korean-ignore rule)
                    # rather than silently discarding Korean audio.
                    # NOTE: update_instructions is intentionally NOT called here.
                    # gemini-3.5-live-translate-preview rejects mid-session instruction
                    # updates with 1007 (invalid argument), which kills the WebSocket
                    # session entirely. Mode state is tracked in caption_tracker only;
                    # the Gemini session continues uninterrupted.
                    logger.info(f"Caption mode updated to: {new_mode} (Gemini session unchanged — model does not support mid-session instruction updates)")
        except Exception as e:
            logger.error(f"Failed to process data packet in agent: {e}", exc_info=True)

    async def send_audio_state(state):
        payload = {
            "type": "audio_state",
            "state": state
        }
        data = json.dumps(payload).encode('utf-8')
        try:
            await ctx.room.local_participant.publish_data(
                payload=data,
                topic="audio_state"
            )
            logger.info(f"Published audio state: {state}")
        except Exception as e:
            logger.error(f"Failed to publish audio state: {e}", exc_info=True)

    async def publish_current_state():
        segments = caption_tracker.get_segments()
        payload = {
            "segments": segments
        }
        data = json.dumps(payload).encode('utf-8')
        try:
            await ctx.room.local_participant.publish_data(
                payload=data,
                topic="caption"
            )
            logger.debug(f"Published segments: {payload}")
        except Exception as e:
            logger.error(f"Failed to publish caption data: {e}", exc_info=True)

    def handle_text_chunk(text: str):
        caption_tracker.handle_agent_chunk(text)
        asyncio.create_task(publish_current_state())

    async def intercept_text_stream(text_stream):
        async for text in text_stream:
            handle_text_chunk(text)
            yield text

    async def intercept_message_stream(message_stream):
        caption_tracker.start_agent_turn()
        
        if caption_tracker.current_mode == "transcription":
            try:
                async for msg in message_stream:
                    async for text in msg.text_stream:
                        pass
            finally:
                caption_tracker.set_agent_is_partial(False)
                caption_tracker.update_agent_text("")
                asyncio.create_task(publish_current_state())
                logger.info("Generation finished (discarded for transcription mode).")
            return

        asyncio.create_task(send_audio_state("playing"))

        try:
            async for msg in message_stream:
                msg.text_stream = intercept_text_stream(msg.text_stream)
                yield msg
        finally:
            caption_tracker.commit_agent_turn()
            asyncio.create_task(publish_current_state())
            asyncio.create_task(send_audio_state("stopped"))
            logger.info("Generation finished.")

    def on_generation_created(ev: llm.GenerationCreatedEvent):
        logger.info("Intercepted generation_created event. Wrapping streams...")
        ev.message_stream = intercept_message_stream(ev.message_stream)

    def on_session_created(sess: llm.RealtimeSession):
        nonlocal llm_session
        llm_session = sess
        logger.info("Realtime LLM Session created. Attaching listeners...")

        # Monkeypatch generate_reply to prevent 1007 WebSocket errors.
        # CRITICAL: Do NOT send ActivityEnd here. Gemini Live Translate is a
        # streaming-only model that manages its own activity lifecycle via
        # the continuous audio stream. Manually injecting ActivityEnd corrupts
        # the model's internal state, causing it to ignore all subsequent
        # audio input and freezing translation after the first utterance.
        # We ONLY need to suppress the LiveClientContent packet that the SDK
        # would otherwise send (which triggers 1007 errors on this model).
        def custom_generate_reply(*args, **kwargs):
            logger.info("Intercepted generate_reply — suppressing LiveClientContent (no ActivityEnd sent).")
            
            # Return a pre-resolved future containing a dummy GenerationCreatedEvent.
            # This makes the SDK's user-initiated task finish immediately and cleanly,
            # without sending any protocol messages to Gemini.
            fut = asyncio.Future()
            
            async def empty_stream():
                if False:
                    yield None
            
            dummy_event = llm.GenerationCreatedEvent(
                message_stream=empty_stream(),
                function_stream=empty_stream(),
                user_initiated=True,
                response_id="dummy-response-id"
            )
            fut.set_result(dummy_event)
            return fut

        sess.generate_reply = custom_generate_reply

        @sess.on("close")
        def on_session_closed(ev):
            logger.info("Realtime session closed.")

    # --- Initialize Gemini Live Translate Model ---
    try:
        model = CustomRealtimeModel(
            model="gemini-3.5-live-translate-preview",
            voice="Aoede",
            instructions=SYSTEM_INSTRUCTION,
            temperature=0.3,  # Low temperature for faithful translation
            input_audio_transcription=types.AudioTranscriptionConfig(),
            output_audio_transcription=types.AudioTranscriptionConfig(),
            # CRITICAL: Disable Gemini's auto activity detection.
            # With it enabled, Gemini misdetects speech pauses as end-of-activity
            # and terminates the generation stream after ~20s, killing translation.
            # Without BOTH local VAD and auto activity detection, Gemini treats
            # the entire audio stream as continuous input — exactly what a
            # streaming translation model needs.
            realtime_input_config=types.RealtimeInputConfig(
                automatic_activity_detection=types.AutomaticActivityDetection(
                    disabled=True
                )
            ),
            on_session_created=on_session_created,
            on_generation_created=on_generation_created
        )
        logger.info("Gemini Live Translate model initialized successfully.")
    except Exception as e:
        logger.error(f"Failed to initialize Gemini model: {e}", exc_info=True)
        raise SystemExit(1) from e

    # --- Start Agent Session ---
    try:
        agent = Agent(instructions=SYSTEM_INSTRUCTION)
        # No VAD, no turn_handling — Gemini Live Translate is a continuous
        # streaming model, not a conversational request-response model.
        # Local VAD triggered generate_reply → dummy events → SDK pipeline
        # contention → session freeze after N utterances.
        session = AgentSession(
            llm=model,
        )
        
        # Initial instructions are applied statically at startup
        pass
        
        # Ensure all speech handles are interruptible at creation.
        # This prevents the SDK from discarding incoming microphone audio with silence frames
        # and avoids "This generation handle does not allow interruptions" RuntimeErrors.
        @session.on("speech_created")
        def on_speech_created(ev: SpeechCreatedEvent):
            logger.info(f"Dynamically allowing interruptions on speech (id: {ev.speech_handle.id}, user_initiated: {ev.user_initiated})")
            ev.speech_handle.allow_interruptions = True
        
        # Monitor user inputs and transcribe them in real time
        @session.on("user_input_transcribed")
        def on_user_transcribed(ev: UserInputTranscribedEvent):
            async def process_user_transcription():
                try:
                    transcript_text = ev.transcript.strip() if ev.transcript else ""
                    if not transcript_text and not ev.is_final:
                        return
                        
                    caption_tracker.handle_user_transcription(transcript_text, ev.is_final)
                    logger.info(f"User Transcribed: '{transcript_text}' (is_final={ev.is_final})")
                    await publish_current_state()
                except Exception as e:
                    logger.error(f"Error in user transcription processing: {e}", exc_info=True)
            
            asyncio.create_task(process_user_transcription())

        await session.start(agent=agent, room=ctx.room)
        logger.info("Agent session started. Translation active — waiting for audio input...")
    except Exception as e:
        logger.error(f"Failed to start agent session: {e}", exc_info=True)
        raise SystemExit(1) from e


# ──────────────────────────────────────────────
# Worker Configuration & CLI
# ──────────────────────────────────────────────

if __name__ == "__main__":
    cli.run_app(
        WorkerOptions(
            entrypoint_fnc=entrypoint,
        )
    )
