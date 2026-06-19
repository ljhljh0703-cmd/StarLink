#!/bin/bash
# =========================================================================
# StarLink — 터미널 기반 iOS 시뮬레이터 원클릭 실행 스크립트
# =========================================================================
# Xcode 무거운 GUI를 켜지 않고 맥북 내부에서 가볍게 앱을 실행하고 
# 오디오 통역/자막 테스트를 수행할 수 있도록 돕는 유틸리티입니다.

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "========================================================================="
echo " 1. iOS 시뮬레이터 빌드 수행 중..."
echo "========================================================================="
# 프로젝트 내부 build 폴더에 빌드 산출물을 고정하여 절대경로 꼬임 방지
xcodebuild -project StarLink.xcodeproj \
           -scheme StarLink \
           -sdk iphonesimulator \
           -derivedDataPath ./build \
           build \
           CODE_SIGNING_ALLOWED=NO \
           -quiet

APP_PATH="$PROJECT_DIR/build/Build/Products/Debug-iphonesimulator/StarLink.app"

echo "========================================================================="
echo " 2. 활성화된 iOS 시뮬레이터 확인 및 부팅 중..."
echo "========================================================================="
# 켜져 있는 시뮬레이터 검사
BOOTED_DEVICE=$(xcrun simctl list devices | grep "Booted" | head -n 1 || true)

if [ -z "$BOOTED_DEVICE" ]; then
    # 켜진 시뮬레이터가 없으면 가장 대중적인 iPhone 15 또는 최신 기기 부팅
    TARGET_DEVICE="iPhone 15"
    echo "부팅된 기기가 없습니다. [$TARGET_DEVICE]를 부팅합니다..."
    
    # 디바이스가 실제로 존재하는지 체크
    DEVICE_ID=$(xcrun simctl list devices | grep -m 1 "$TARGET_DEVICE" | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -n 1 || true)
    
    if [ -z "$DEVICE_ID" ]; then
        # 목록에서 첫 번째 iOS 디바이스 ID 추출 (fallback)
        DEVICE_ID=$(xcrun simctl list devices | grep -A 15 "iOS" | grep -v "Unavailable" | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -n 1 || true)
    fi
    
    if [ -z "$DEVICE_ID" ]; then
        echo "오류: 시뮬레이터 디바이스를 찾을 수 없습니다. Xcode가 올바르게 설치되었는지 확인하십시오."
        exit 1
    fi
    
    xcrun simctl boot "$DEVICE_ID"
else
    echo "이미 켜져 있는 시뮬레이터를 재사용합니다: $BOOTED_DEVICE"
fi

# 시뮬레이터 GUI 앱 실행 (창 띄우기)
open -a Simulator

echo "========================================================================="
echo " 3. 시뮬레이터에 StarLink 앱 설치 및 실행 중..."
echo "========================================================================="
# 부팅된 시뮬레이터에 앱 설치
xcrun simctl install booted "$APP_PATH"

# 앱 실행
BUNDLE_ID="com.godju.starlink.app"
xcrun simctl launch booted "$BUNDLE_ID"

echo "========================================================================="
echo " 🎉 실행 성공! 시뮬레이터 내에서 StarLink 앱이 기동되었습니다."
echo " 💡 맥북 마이크와 스피커를 시뮬레이터가 공유하므로 바로 테스트할 수 있습니다."
echo "========================================================================="
