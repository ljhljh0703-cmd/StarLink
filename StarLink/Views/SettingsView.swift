// SettingsView.swift
// StarLink — Premium Hearing Aid & Wireless Earphones Translation
//
// User configuration sheet enabling "Bring Your Own Key" (BYOK) runtime settings.
// Stored in UserDefaults and dynamically updates AppConfig constants.

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var livekitURL: String = ""
    @State private var livekitToken: String = ""
    @State private var tokenServerURL: String = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Introduction Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("사용자 연결 설정 (BYOK)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.accentBlue)
                            
                            Text("본인 소유의 LiveKit 클라우드와 번역 에이전트를 연동하여 개별 API 비용으로 독립 가동할 수 있습니다. 빈칸으로 저장할 경우 앱에 탑재된 빌드 기본 설정값으로 연결됩니다.")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Theme.textSecondary)
                                .lineSpacing(4)
                        }
                        .padding(.top, 8)
                        
                        // Form Fields
                        VStack(spacing: 20) {
                            // LiveKit URL
                            VStack(alignment: .leading, spacing: 6) {
                                Text("LiveKit 서버 주소 (URL)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                
                                TextField("wss://your-project.livekit.cloud", text: $livekitURL)
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Theme.surface)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Theme.border, lineWidth: 1)
                                    )
                                    .foregroundStyle(Theme.textPrimary)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                            }
                            
                            // LiveKit Token
                            VStack(alignment: .leading, spacing: 6) {
                                Text("로컬 개발용 정적 토큰 (Static Token)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                
                                TextField("임시 연결용 JWT 토큰 입력", text: $livekitToken)
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Theme.surface)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Theme.border, lineWidth: 1)
                                    )
                                    .foregroundStyle(Theme.textPrimary)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            
                            // Token Server URL
                            VStack(alignment: .leading, spacing: 6) {
                                Text("동적 토큰 발급 서버 주소 (Token Server URL)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                
                                TextField("https://your-backend.com/api/token", text: $tokenServerURL)
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Theme.surface)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Theme.border, lineWidth: 1)
                                    )
                                    .foregroundStyle(Theme.textPrimary)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                            }
                        }
                        
                        // Action Buttons
                        VStack(spacing: 12) {
                            Button {
                                saveSettings()
                                dismiss()
                            } label: {
                                Text("설정 저장")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Color.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Theme.accentBlue)
                                    .cornerRadius(12)
                            }
                            
                            Button {
                                clearSettings()
                            } label: {
                                Text("기본값으로 초기화")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.errorRed)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Theme.errorRed.opacity(0.1))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Theme.errorRed.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.top, 16)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("연결 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .onAppear(perform: loadSettings)
        }
        .preferredColorScheme(.dark)
    }
    
    private func loadSettings() {
        livekitURL = UserDefaults.standard.string(forKey: "custom_livekit_url") ?? ""
        livekitToken = UserDefaults.standard.string(forKey: "custom_livekit_token") ?? ""
        tokenServerURL = UserDefaults.standard.string(forKey: "custom_token_server_url") ?? ""
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(livekitURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "custom_livekit_url")
        UserDefaults.standard.set(livekitToken.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "custom_livekit_token")
        UserDefaults.standard.set(tokenServerURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "custom_token_server_url")
    }
    
    private func clearSettings() {
        livekitURL = ""
        livekitToken = ""
        tokenServerURL = ""
        UserDefaults.standard.removeObject(forKey: "custom_livekit_url")
        UserDefaults.standard.removeObject(forKey: "custom_livekit_token")
        UserDefaults.standard.removeObject(forKey: "custom_token_server_url")
    }
}
