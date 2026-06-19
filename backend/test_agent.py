import unittest
import sys
import os

# Add parent directory to path to allow import
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from agent import detect_language, extract_completed_sentences, CaptionStateTracker


class TestAgentHelpers(unittest.TestCase):
    def test_detect_language_korean(self):
        self.assertEqual(detect_language("안녕하세요"), "ko")
        self.assertEqual(detect_language("이것은 한국어 테스트입니다."), "ko")

    def test_detect_language_english(self):
        self.assertEqual(detect_language("Hello world, this is a test."), "en")
        # Mixed hungul and english should prefer hangul since Hangul block check comes first
        self.assertEqual(detect_language("Hello 안녕하세요"), "ko")

    def test_detect_language_japanese(self):
        self.assertEqual(detect_language("こんにちは"), "ja")

    def test_detect_language_chinese(self):
        self.assertEqual(detect_language("你好"), "zh")

    def test_detect_language_unknown(self):
        self.assertEqual(detect_language(""), "unknown")
        self.assertEqual(detect_language("12345!@#"), "unknown")

    def test_extract_completed_sentences(self):
        # English splitting
        completed, remaining = extract_completed_sentences("Hello. How are you? I am fine")
        self.assertEqual(completed, ["Hello.", "How are you?"])
        self.assertEqual(remaining, "I am fine")

        # Empty/None values
        completed, remaining = extract_completed_sentences("")
        self.assertEqual(completed, [])
        self.assertEqual(remaining, "")

        # Asian punctuation
        completed, remaining = extract_completed_sentences("안녕하세요。 반갑습니다！ 날씨가 좋네요")
        self.assertEqual(completed, ["안녕하세요。", "반갑습니다！"])
        self.assertEqual(remaining, "날씨가 좋네요")

    def test_detect_language_complex(self):
        # Mixed language cases
        self.assertEqual(detect_language("Hello. こんにちは"), "ja")  # Contains Japanese character
        self.assertEqual(detect_language("안녕하세요 こんにちは"), "ko")  # Contains Korean character (ko check comes first)
        self.assertEqual(detect_language("Hello World! 123"), "en")     # Latin ratio > 30%
        self.assertEqual(detect_language("123 456"), "unknown")          # No letters

    def test_extract_completed_sentences_edge_cases(self):
        # Multiple ending symbols
        completed, remaining = extract_completed_sentences("Really?! Yes...")
        self.assertEqual(completed, ["Really?!", "Yes..."])
        self.assertEqual(remaining, "")

        # No ending symbols
        completed, remaining = extract_completed_sentences("No punctuation here")
        self.assertEqual(completed, [])
        self.assertEqual(remaining, "No punctuation here")

        # Spaces inside and outside
        completed, remaining = extract_completed_sentences("  Hello!   World.   Next ")
        self.assertEqual(completed, ["Hello!", "World."])
        self.assertEqual(remaining, "Next")


class TestCaptionStateTracker(unittest.TestCase):
    def setUp(self):
        self.tracker = CaptionStateTracker()

    def test_initial_state(self):
        segments = self.tracker.get_segments()
        self.assertEqual(len(segments), 0)

    def test_user_active_text_partial(self):
        self.tracker.update_user_text("Hello this is")
        segments = self.tracker.get_segments()
        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0]["original"], "Hello this is")
        self.assertEqual(segments[0]["translated"], "")
        self.assertTrue(segments[0]["isPartial"])

    def test_user_active_text_completed(self):
        self.tracker.update_user_text("Hello this is a test. How")
        segments = self.tracker.get_segments()
        # Should split "Hello this is a test." into user_active_completed and "How" as remaining
        self.assertEqual(len(segments), 2)
        self.assertEqual(segments[0]["original"], "Hello this is a test.")
        self.assertEqual(segments[1]["original"], "How")
        self.assertTrue(segments[0]["isPartial"])
        self.assertTrue(segments[1]["isPartial"])

    def test_translation_mode_alignment(self):
        # 1. User speaks one full sentence, and starts second
        self.tracker.update_user_text("Hello. How are")
        
        # 2. Mock that the first sentence is committed (e.g. from user_input_transcribed with is_final)
        # In agent.py, when ev.is_final is True, it appends completed to user_completed_sentences and resets current_user_text.
        # Let's simulate:
        completed, remaining = extract_completed_sentences(self.tracker.current_user_text)
        self.tracker.add_user_completed(completed)
        self.tracker.update_user_text(remaining)
        
        # Now user_completed = ["Hello."], active_user = "How are"
        self.assertEqual(self.tracker.user_completed_sentences, ["Hello."])
        self.assertEqual(self.tracker.current_user_text, "How are")
        
        # 3. Agent (translator) starts translating the first sentence
        self.tracker.update_agent_text("안녕")
        self.tracker.set_agent_is_partial(True)
        
        segments = self.tracker.get_segments()
        self.assertEqual(len(segments), 2)
        # Turn 1: original="Hello.", translated="안녕" (agent active buffer), is_partial should be True because agent is still partial on turn 1
        self.assertEqual(segments[0]["original"], "Hello.")
        self.assertEqual(segments[0]["translated"], "안녕")
        self.assertTrue(segments[0]["isPartial"])
        
        # Turn 2: original="How are", translated="", is_partial=True
        self.assertEqual(segments[1]["original"], "How are")
        self.assertEqual(segments[1]["translated"], "")
        self.assertTrue(segments[1]["isPartial"])

        # 4. Agent finishes first sentence translation
        # In agent.py, when stream finishes:
        # completed, remaining = extract_completed(agent_text)
        # agent_completed.extend(completed) + remaining
        agent_completed, agent_remaining = extract_completed_sentences(self.tracker.current_agent_text)
        self.tracker.add_agent_completed(agent_completed)
        if agent_remaining:
            self.tracker.add_agent_completed([agent_remaining])
        self.tracker.update_agent_text("")
        self.tracker.set_agent_is_partial(False)
        
        # Now agent_completed = ["안녕"], active_agent = "", agent_is_partial = False
        segments = self.tracker.get_segments()
        # Since turn-1 original ("Hello.") is in user_completed, and translated ("안녕") is in agent_completed,
        # and both are completed, isPartial for turn-1 should be False!
        self.assertEqual(segments[0]["original"], "Hello.")
        self.assertEqual(segments[0]["translated"], "안녕")
        self.assertFalse(segments[0]["isPartial"])

    def test_transcription_mode(self):
        self.tracker.set_mode("transcription")
        self.tracker.update_user_text("Hello. How are")
        
        # In transcription mode, translated should mirror original, and partial is determined by whether the index is completed.
        segments = self.tracker.get_segments()
        self.assertEqual(len(segments), 2)
        # Turn 1: "Hello." (active completed, but not in user_completed_sentences yet)
        self.assertEqual(segments[0]["original"], "Hello.")
        self.assertEqual(segments[0]["translated"], "Hello.")
        self.assertTrue(segments[0]["isPartial"])  # since i < len(user_completed_sentences) (which is 0) is False

        # Now commit the completed sentence
        completed, remaining = extract_completed_sentences(self.tracker.current_user_text)
        self.tracker.add_user_completed(completed)
        self.tracker.update_user_text(remaining)
        
        segments = self.tracker.get_segments()
        self.assertEqual(segments[0]["original"], "Hello.")
        self.assertEqual(segments[0]["translated"], "Hello.")
        self.assertFalse(segments[0]["isPartial"]) # now user_completed_sentences has ["Hello."], so i < 1 is True

    def test_trimming_segments(self):
        # Insert 105 completed sentences
        self.tracker.user_completed_sentences = [f"User {i}" for i in range(105)]
        self.tracker.agent_completed_sentences = [f"Agent {i}" for i in range(105)]
        segments = self.tracker.get_segments()
        # Should trim to 100
        self.assertEqual(len(segments), 100)
        self.assertEqual(segments[0]["id"], "turn-6")
        self.assertEqual(segments[-1]["id"], "turn-105")

    def test_tracker_repeated_updates(self):
        # Changing mode resets/affects output formatting
        self.tracker.update_user_text("Input text")
        self.tracker.set_mode("transcription")
        segments = self.tracker.get_segments()
        self.assertEqual(segments[0]["original"], "Input text")
        self.assertEqual(segments[0]["translated"], "Input text") # mirrored in transcription mode
        
        self.tracker.set_mode("translation")
        segments2 = self.tracker.get_segments()
        self.assertEqual(segments2[0]["original"], "Input text")
        self.assertEqual(segments2[0]["translated"], "") # empty in translation mode

    def test_handle_user_transcription(self):
        # 1. Partial updates
        self.tracker.handle_user_transcription("Hello world", is_final=False)
        self.assertEqual(self.tracker.current_user_text, "Hello world")
        self.assertEqual(len(self.tracker.user_completed_sentences), 0)

        # 2. Final update with completed sentence
        self.tracker.handle_user_transcription("Hello world. How are you", is_final=True)
        self.assertEqual(self.tracker.current_user_text, "")
        self.assertEqual(self.tracker.user_completed_sentences, ["Hello world.", "How are you"])

    def test_handle_agent_chunk_and_commit(self):
        # 1. Start agent turn
        self.tracker.start_agent_turn()
        self.assertTrue(self.tracker.agent_is_partial)
        self.assertEqual(self.tracker.agent_transcript, "")
        self.assertEqual(self.tracker.current_agent_text, "")

        # 2. Add chunks
        self.tracker.handle_agent_chunk("안녕")
        self.tracker.handle_agent_chunk("하세요. 반갑")
        self.assertEqual(self.tracker.agent_transcript, "안녕하세요. 반갑")
        self.assertEqual(self.tracker.current_agent_text, "안녕하세요. 반갑")

        # 3. Commit turn
        self.tracker.commit_agent_turn()
        self.assertFalse(self.tracker.agent_is_partial)
        self.assertEqual(self.tracker.current_agent_text, "")
        self.assertEqual(self.tracker.agent_completed_sentences, ["안녕하세요.", "반갑"])


if __name__ == "__main__":
    unittest.main()
