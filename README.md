<div align="center">

# 🎙️ StarLink

**Real-Time Simultaneous Translation for Wireless Earphones & Bluetooth Audio**

Translate ambient English, Japanese, and Chinese speech into Korean — streamed directly to your AirPods, Galaxy Buds, Bluetooth earbuds, or MFi hearing devices with sub-second latency.

[![iOS 17+](https://img.shields.io/badge/iOS-17%2B-blue?logo=apple&logoColor=white)](https://developer.apple.com/ios/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)](https://swift.org/)
[![Gemini 3.5 Live](https://img.shields.io/badge/Gemini-3.5%20Live-4285F4?logo=google&logoColor=white)](https://ai.google.dev/)
[![LiveKit WebRTC](https://img.shields.io/badge/LiveKit-2.0-purple?logo=livekit&logoColor=white)](https://livekit.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

## 📖 Overview

**StarLink** is an iOS application and backend agent system designed for **hands-free, real-time simultaneous translation** through wireless audio devices. 

By pairing a mobile device (iPhone) with any Bluetooth earphone (such as AirPods or Galaxy Buds) or MFi (Made for iPhone) hearing aids, the system captures ambient foreign speech, streams it through a low-latency WebRTC connection to a backend agent powered by **Gemini 3.5 Live Translate**, and delivers natural-sounding Korean speech directly into the user's ears. It also displays real-time synchronized subtitles on-screen with automatic input language detection.

---

## ⚡ Core Engineering Challenges Solved (Portfolio Highlights)

This project addresses several complex real-time audio engineering and WebRTC challenges in iOS:

### 1. Bluetooth & MFi Audio Routing Control (WebRTC Bypass)
* **Challenge**: LiveKit’s automatic audio configuration resets the iOS `AVAudioSession` category, causing WebRTC to route audio to the iPhone's internal receiver (earpiece) instead of connected Bluetooth earphones or MFi hearing devices.
* **Solution**: Bypassed LiveKit's auto-configuration (`isAutomaticConfigurationEnabled = false`) and implemented manual control. Wrapped routing configurations within WebRTC configuration locks (`LKRTCAudioSession.sharedInstance().lockForConfiguration()`), and forced category options supporting Bluetooth (`.allowBluetooth`, `.allowBluetoothA2DP`, `.allowAirPlay`, and `.defaultToSpeaker`) to preserve the Bluetooth output route.

### 2. Acoustic Feedback Loop Prevention (VAD & Mute Guard)
* **Challenge**: Translated audio playing through the earphones can leak back into the iPhone's microphone, causing the AI agent to hear its own translated voice and re-translate it, triggering an infinite echo loop.
* **Solution**: Developed a semi-duplex audio control mechanism. Intercepted the remote participant's Voice Activity Detection (`isAISpeakingByVAD`) event. The moment the AI agent begins streaming audio, the local mic track is immediately muted. Once the AI finishes speaking, the microphone remains muted for a **500ms safety buffer** to clear acoustic reverberations before unmuting.

### 3. Voice-Subtitle Modality Synchronization
* **Challenge**: The Gemini Live voice-to-voice model generates raw audio packets. In its default state, it does not send the corresponding transcription stream, leaving on-screen subtitles stuck in a loading state.
* **Solution**: Wrapped the Gemini session initialization with custom `AudioTranscriptionConfig` parameters on both input and output streams. This forces the model to emit simultaneous transcription tokens, which are captured, parsed, and pushed to the SwiftUI view in sync with the audio playback.

### 4. Zero-Latency Input Language Detection
* **Challenge**: Translating multi-language conversations requires showing the source language (e.g. English, Japanese, Chinese) to the user. Using external translation APIs to detect language introduces unacceptable network latency.
* **Solution**: Built a lightweight, 0ms-latency Unicode range block analyzer (`detect_language`) on the backend. It maps character sets (Hangul, Hiragana/Katakana, CJK Hanzi, Latin) of streaming segments, packages the language code, and transmits it via the LiveKit data channel to render glassmorphic language badges (`[영어]`, `[일본어]`, etc.) in real time.

---

## 🏗️ Architecture & Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        iPhone (StarLink App)                    │
│                                                                 │
│  ┌──────────┐    ┌──────────────┐    ┌───────────────────────┐  │
│  │ Mic      │───▶│ LiveKit SDK  │◀──▶│ Audio Session Manager │  │
│  │ (Ambient)│    │ (Room Client)│    │ (MFi/Bluetooth Route) │  │
│  └──────────┘    └──────┬───────┘    └──────────┬────────────┘  │
│                         │                       │               │
│                         │ WebRTC (Audio Track)  │ Bluetooth     │
│                         │                       │               │
│                         ▼                       ▼               │
│                  ┌──────────────┐        ┌──────────────┐       │
│                  │ Caption View │        │ AirPods /    │       │
│                  │ (SwiftUI UI) │        │ Earphones    │       │
│                  └──────────────┘        └──────────────┘       │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      │ WebRTC (Bi-directional Audio & Data)
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    LiveKit Cloud / Server                       │
│              (Low-latency Media Routing Engine)                 │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      │ WebRTC (Audio & Data Streams)
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Backend Agent (Python)                        │
│                                                                 │
│  ┌─────────────────┐    ┌──────────────────────────────────┐    │
│  │ livekit-agents   │───▶│ Gemini 3.5 Live Translate       │    │
│  │ (Room Subscriber)│◀───│ (Audio-to-Audio / EN-JA-ZH->KO)  │    │
│  └─────────────────┘    └──────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

1. **Audio Capture**: The iPhone microphone captures ambient foreign speech.
2. **Uplink Streaming**: The LiveKit SDK publishes the local audio track to the room.
3. **AI Translation**: The Python agent receives the audio track, forwards it to Gemini 3.5 Live, and translates it into Korean.
4. **Subtitles Delivery**: The agent parses the source language and publishes transcription data to the LiveKit data channel under the topic `caption`.
5. **Downlink Playback**: The iOS client receives the translated audio track. The customized `AVAudioSession` manager routes this stream directly to the connected AirPods/earphones.
6. **UI Render**: SwiftUI decodes the JSON payload, rendering captions alongside their detected language badge (e.g. `[영어]`, `[일본어]`).

---

## 📂 Project Structure

```
StarLink/
├── project.yml              # XcodeGen project specification
├── README.md                # This file
├── LICENSE                  # MIT Open-source License
├── .gitignore               # Git exclude rules
├── StarLink/                # iOS App Sources
│   ├── Info.plist           # App configuration & permissions
│   ├── Config/              # App Config (AppConfig.swift)
│   ├── Secrets.plist.example # App credentials template
│   ├── Secrets.plist        # Local private keys (git-ignored)
│   ├── Managers/            # Audio Session & LiveKit managers
│   ├── Models/              # Data models (CaptionEntry)
│   └── Views/               # SwiftUI Views (CaptionScrollView, StatusBar)
└── backend/                 # Python Backend
    ├── agent.py             # Translation Agent (Gemini Live)
    ├── server.py            # Token Server (Dynamic Token Issuer)
    ├── generate_token.py    # Local token generation utility
    ├── requirements.txt     # Python dependencies
    ├── .env.example         # Environment template
    └── .env                 # Local credentials (git-ignored)
```

---

## ⚙️ Setup & Installation

### 1. Prerequisites

* **Xcode 16.0+** (iOS 17 SDK)
* **XcodeGen** (`brew install xcodegen`)
* **Python 3.11+**
* **LiveKit Cloud account** ([cloud.livekit.io](https://cloud.livekit.io))
* **Google Gemini API Key** ([aistudio.google.com](https://aistudio.google.com/apikey))
* **Physical iOS Device** (AirPods/Bluetooth audio routing cannot be tested on Simulator)

---

### 2. Configure Credentials

#### iOS Client Setup (Static / Pre-configured Mode)
1. Duplicate the credentials template:
   ```bash
   cp StarLink/Secrets.plist.example StarLink/Secrets.plist
   ```
2. Open `StarLink/Secrets.plist` and input your LiveKit WebSocket URL:
   * `LIVEKIT_URL`: `wss://your-project.livekit.cloud`
   * `LIVEKIT_TOKEN`: (Optional) Static JWT token for development.
   * `TOKEN_SERVER_URL`: (Optional) The URL of your deployed Token Server (e.g., `https://your-backend.com/api/token`). If defined, the app will dynamically fetch short-lived tokens on startup.
3. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```
4. Open `StarLink.xcodeproj`, set your **Development Team** under Target -> Signing & Capabilities, and build/run on your physical iPhone.

#### 🔑 Bring Your Own Key (BYOK) Mode (For App Store Release)
To avoid server hosting and API usage costs for a public release, the app includes a **Settings UI** (accessible via the Gear icon in the top status bar) enabling runtime configuration:
* Tap the **Gear** icon in the status bar.
* Input your own `LIVEKIT_URL`, static `LIVEKIT_TOKEN`, or dynamic `TOKEN_SERVER_URL`.
* Tap **Save Settings** to persist the configuration in `UserDefaults`.
* *Note: When configured, user-defined inputs override default compile-time keys. Tap **Reset to Defaults** to clear these overrides.*

#### 📱 Sideloading with a Free Apple Developer Account (For Portfolio Video Demo)
You do not need a paid developer membership ($99/year) to capture your working demo video:
1. Connect your physical iPhone to your Mac via USB.
2. Open `StarLink.xcodeproj` in Xcode, select the **StarLink** target -> **Signing & Capabilities**.
3. Under **Team**, select your personal Apple ID (Xcode will generate a free provisioning profile).
4. Build and run the app on your device.
5. On your iPhone, go to **Settings** -> **General** -> **VPN & Device Management** and tap **Trust** on your developer certificate.
*Note: Apps signed with a free developer certificate expire and must be re-signed every **7 days**, which is ideal for testing and recording demo videos.*

#### Backend Setup
1. Navigate to the backend directory:
   ```bash
   cd backend
   ```
2. Create and activate a virtual environment:
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   ```
3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
4. Duplicate the environment variables template:
   ```bash
   cp .env.example .env
   ```
5. Open `backend/.env` and add your LiveKit credentials and Gemini API Key:
   ```env
   LIVEKIT_URL=wss://your-project.livekit.cloud
   LIVEKIT_API_KEY=your_livekit_api_key
   LIVEKIT_API_SECRET=your_livekit_api_secret
   GOOGLE_API_KEY=your_google_api_key
   ```

---

### 3. Run the System

#### A. Start the Translation Agent
The agent subscribes to the room, connects to Gemini, translates incoming speech, and publishes the audio/subtitles.
```bash
cd backend
source venv/bin/activate
python agent.py dev
```

#### B. Start the Token Server (Optional)
To run in a secure production mode, launch the token server to issue 1-hour expiration JWTs:
```bash
cd backend
source venv/bin/activate
python server.py
```
By default, the server runs on `http://localhost:8080`.

#### C. Run the iOS App
Connect your AirPods or Bluetooth earbuds to your iPhone, launch the **StarLink** app, and tap the translation toggle to begin.

---

## 🛠️ Troubleshooting

### iOS App Issues
* **Audio routes to Phone Speaker / Earpiece**: Make sure your earphones are paired and active. If routing fails, toggle Bluetooth in iOS Settings or ensure Bluetooth permission is granted to StarLink.
* **Captions stuck loading**: Make sure the backend agent is running and has a stable connection to LiveKit and Gemini. Check that the Gemini API Key has sufficient quota.
* **SPM Package errors**: Reset Xcode package cache: `File` -> `Packages` -> `Reset Package Caches`.

### Backend Agent Issues
* **`GOOGLE_API_KEY` not found**: Ensure your `.env` contains the correct key and is loaded.
* **Agent connects but stays silent**: Check that you are speaking clearly in a supported language (English, Japanese, Chinese). Low-quality microphone inputs or loud background noise might be filtered by the agent's noise isolation rules.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE) - see the file for details.

*Built for hands-free accessibility and real-time cross-language communication.*
