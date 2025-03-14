import SwiftUI
import AppKit

// Helper to keep sheet from dismissing - using NSViewRepresentable for better performance
struct SheetStayVisibleModifier: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window, window.isSheet {
                // Make the sheet stay visible when interacting with it
                NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
                    window.makeKeyAndOrderFront(nil)
                    return event
                }
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var token: String = ""
    @State private var username: String = ""
    @State private var showSuccess: Bool = false
    @State private var showAddAppSheet: Bool = false
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            githubSettingsTab
                .tabItem {
                    Label("GitHub", systemImage: "person.crop.circle")
                }
                .tag(0)
            
            appLaunchersTab
                .tabItem {
                    Label("App Launchers", systemImage: "app.badge.plus")
                }
                .tag(1)
            
            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(2)
        }
        .frame(width: 450, height: 500)
        .onAppear {
            // Load values only when view appears
            token = appState.githubToken
            username = appState.username
        }
    }
    
    // GitHub Settings Tab
    private var githubSettingsTab: some View {
        Form {
            Section(header: Text("GitHub Configuration")) {
                TextField("GitHub Username", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                SecureField("GitHub Personal Access Token", text: $token)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Text("Your token needs 'repo' and 'user' scopes for full functionality")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Link("How to create a GitHub token", destination: URL(string: "https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens")!)
                    .font(.caption)
                
                HStack {
                    Spacer()
                    
                    Button("Save Changes") {
                        appState.githubToken = token
                        appState.username = username
                        appState.saveSettings()
                        showSuccess = true
                        
                        // Auto-hide success message after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            showSuccess = false
                        }
                    }
                    .disabled(token.isEmpty || username.isEmpty || (token == appState.githubToken && username == appState.username))
                    
                    Spacer()
                }
                .padding(.top)
                
                if showSuccess {
                    Text("Settings saved successfully!")
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                        .transition(.opacity)
                        .animation(.easeInOut, value: showSuccess)
                }
            }
        }
        .padding(20)
    }
    
    // App Launchers Tab
    private var appLaunchersTab: some View {
        VStack {
            HStack {
                Text("Custom App Launchers")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    showAddAppSheet = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(.horizontal)
            .padding(.top)
            
            if appState.customAppLaunchers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "apps.iphone")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                    
                    Text("No custom apps added yet")
                        .foregroundColor(.secondary)
                    
                    Button("Add App") {
                        showAddAppSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.customAppLaunchers) { app in
                        appLauncherRow(app)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            appState.removeCustomAppLauncher(at: index)
                        }
                    }
                }
                .padding(.horizontal, -10)
            }
        }
        .padding()
        .sheet(isPresented: $showAddAppSheet) {
            AddAppView(isPresented: $showAddAppSheet)
                .environmentObject(appState)
                .frame(width: 400, height: 320)
                .background(
                    SheetStayVisibleModifier()
                )
        }
    }
    
    // App Launcher Row to optimize rendering
    @ViewBuilder
    private func appLauncherRow(_ app: CustomAppLauncher) -> some View {
        HStack {
            Image(systemName: app.imageName)
                .frame(width: 24)
            
            VStack(alignment: .leading) {
                Text(app.name)
                    .fontWeight(.medium)
                
                if let path = app.appPath {
                    Text(path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if let url = app.urlString {
                    Text(url)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    // About Tab
    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("About Personal Dashboard")
                    .font(.headline)
                
                Text("A native macOS dashboard application for developers")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Features")
                    .font(.headline)
                
                featuresGroup
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
    
    // Group features to optimize rendering
    private var featuresGroup: some View {
        Group {
            FeatureItem(icon: "chart.bar.fill", text: "GitHub contribution tracking")
            FeatureItem(icon: "folder.fill", text: "Recent repositories access")
            FeatureItem(icon: "apps.iphone", text: "Quick app launcher")
            FeatureItem(icon: "gearshape.fill", text: "Customizable app launchers")
        }
    }
}

struct FeatureItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.blue)
            
            Text(text)
                .font(.body)
        }
        .padding(.vertical, 2)
    }
} 