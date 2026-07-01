import SwiftUI

struct ThemePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FGConstants.appThemeKey) private var currentThemeRaw = AppTheme.classic.rawValue
    @State private var selectedTheme: String = AppTheme.classic.rawValue
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Appearance")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Picker
            HStack(spacing: 32) {
                ThemeOptionView(
                    theme: .classic,
                    imageName: "ThemeClassic",
                    currentTheme: $selectedTheme
                )
                
                ThemeOptionView(
                    theme: .modern,
                    imageName: "ThemeModern",
                    currentTheme: $selectedTheme
                )
            }
            .padding(.vertical, 30)
            .padding(.horizontal, 40)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Apply") {
                    currentThemeRaw = selectedTheme
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(selectedTheme == currentThemeRaw)
            }
            .padding()
        }
        .frame(width: 500)
        .onAppear {
            selectedTheme = currentThemeRaw
        }
    }
}

struct ThemeOptionView: View {
    let theme: AppTheme
    let imageName: String
    @Binding var currentTheme: String
    
    var isSelected: Bool {
        currentTheme == theme.rawValue
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Background/Selection Container
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .frame(width: 220, height: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                
                // Image
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 140)
            }
            .onTapGesture {
                currentTheme = theme.rawValue
            }
            
            Text(theme.rawValue)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
        }
    }
}
