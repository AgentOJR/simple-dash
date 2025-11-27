import SwiftUI
import AppKit

// Helper extension for strong sheets
extension View {
    func withStrongSheet() -> some View {
        self.background(SheetStrongifier())
    }
}

// Helper view to strengthen sheet presentation
struct SheetStrongifier: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window, window.isSheet {
                // Register for click events window-wide
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

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sheetManager: SheetManager
    @State private var selectedMonth: Date = Date()
    @State private var filteredContributions: [ContributionDay] = []
    @State private var contributionGraphData: [[ContributionDay?]] = []
    
    // Constant for sheet identifier
    private let addAppSheetId = "addAppSheet"
    
    // Array of last 12 months for the selector
    private var last12Months: [Date] {
        let calendar = Calendar.current
        let currentDate = Date()
        return (0..<12).map { monthOffset in
            calendar.date(byAdding: .month, value: -monthOffset, to: currentDate)!
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if appState.githubToken.isEmpty || appState.username.isEmpty {
                SetupView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Welcome to Your Dashboard")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        contributionGraphSection
                        
                        Divider()
                        
                        recentRepositoriesSection
                        
                        Divider()
                        
                        appLaunchersSection
                    }
                    .padding()
                }
                .frame(width: 450, height: 550)
            }
        }
        .onAppear {
            // Always update to current date when view appears
            selectedMonth = Date()
            
            if !appState.githubToken.isEmpty && !appState.username.isEmpty {
                appState.fetchGitHubData()
            }
        }
        .onChange(of: selectedMonth) { _ in
            processContributionData()
        }
        .onChange(of: appState.contributionData) { _ in
            processContributionData()
        }
        .sheet(isPresented: Binding<Bool>(
            get: { sheetManager.isSheetActive(addAppSheetId) },
            set: { isActive in
                if isActive {
                    sheetManager.showSheet(addAppSheetId)
                } else {
                    sheetManager.hideSheet(addAppSheetId)
                }
            }
        )) {
            ManagedAddAppView(sheetId: addAppSheetId)
                .environmentObject(appState)
                .environmentObject(sheetManager)
                .frame(width: 400, height: 320)
        }
    }
    
    private func processContributionData() {
        // Filter contributions for selected month
        filteredContributions = filterContributionsByMonth(appState.contributionData, for: selectedMonth)
        
        // Process data for contribution graph by organizing into weeks
        contributionGraphData = processContributionGraphData(filteredContributions, for: selectedMonth)
    }
    
    // Contribution Graph Section
    private var contributionGraphSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GitHub Contributions")
                    .font(.headline)
                
                Spacer()
                
                // Add refresh button
                Button(action: {
                    selectedMonth = Date()
                    appState.fetchGitHubData()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Refresh data")
                
                monthSelector
            }
            
            if appState.isLoading && appState.contributionData.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if appState.contributionData.isEmpty {
                Text("No contribution data available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                contributionGraph
            }
        }
    }
    
    // Month selector picker
    private var monthSelector: some View {
        Picker("Month", selection: $selectedMonth) {
            ForEach(last12Months, id: \.self) { date in
                Text(monthYearFormatter.string(from: date))
                    .tag(date)
            }
        }
        .pickerStyle(MenuPickerStyle())
        .frame(width: 120)
    }
    
    // Process data for contribution graph by organizing into weeks
    private func processContributionGraphData(_ contributions: [ContributionDay], for date: Date) -> [[ContributionDay?]] {
        // Get the date range for the selected month
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        
        guard let startDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return []
        }
        
        // Get the last day of the month
        let nextMonth = month == 12 ? 1 : month + 1
        let nextMonthYear = month == 12 ? year + 1 : year
        guard let nextMonthDate = calendar.date(from: DateComponents(year: nextMonthYear, month: nextMonth, day: 1)),
              let endDate = calendar.date(byAdding: .day, value: -1, to: nextMonthDate) else {
            return []
        }
        
        // Create a lookup dictionary for fast access to contribution data
        var contributionLookup: [String: ContributionDay] = [:]
        for day in contributions {
            contributionLookup[day.date] = day
        }
        
        // Find the first day of the week containing the first day of the month
        var weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate))!
        // If weekStart is after startDate, go back one week
        if weekStart > startDate {
            weekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart)!
        }
        
        // Calculate how many weeks we need to display
        let numberOfWeeks = calendar.dateComponents([.weekOfYear], from: weekStart, to: endDate).weekOfYear! + 1
        
        // Create a 2D array of weeks and days
        var weeks: [[ContributionDay?]] = Array(repeating: Array(repeating: nil, count: 7), count: numberOfWeeks)
        
        // Fill in the weeks array
        var currentDate = weekStart
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        
        for week in 0..<numberOfWeeks {
            for day in 0..<7 {
                let dateString = dateFormatter.string(from: currentDate)
                
                // Check if this date is within our month and if we have contribution data for it
                if calendar.component(.month, from: currentDate) == month {
                    weeks[week][day] = contributionLookup[dateString]
                }
                
                // Move to the next day
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            }
        }
        
        return weeks
    }
    
    // Filter contributions to only show the selected month
    private func filterContributionsByMonth(_ contributions: [ContributionDay], for date: Date) -> [ContributionDay] {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        
        return contributions.filter { contribution in
            if let contributionDate = dateFormatter.date(from: contribution.date) {
                let contributionMonth = calendar.component(.month, from: contributionDate)
                let contributionYear = calendar.component(.year, from: contributionDate)
                return contributionMonth == month && contributionYear == year
            }
            return false
        }
    }
    
    // GitHub Contribution Graph
    private var contributionGraph: some View {
        VStack(alignment: .leading, spacing: 8) {
            if contributionGraphData.isEmpty {
                Text("No contributions for \(monthYearFormatter.string(from: selectedMonth))")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // Day of week labels
                    HStack(spacing: 4) {
                        ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                            Text(day)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .frame(width: 14)
                        }
                    }
                    .padding(.leading, 8)
                    
                    // Contribution grid
                    ContributionGrid(data: contributionGraphData)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            }
            
            HStack {
                Text("Less")
                    .font(.caption)
                
                Spacer()
                
                ForEach(["#ebedf0", "#9be9a8", "#40c463", "#30a14e", "#216e39"], id: \.self) { color in
                    Rectangle()
                        .fill(Color(hex: color))
                        .frame(width: 12, height: 12)
                }
                
                Text("More")
                    .font(.caption)
            }
        }
    }
    
    // Recent Repositories Section
    private var recentRepositoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Repositories")
                .font(.headline)
            
            if appState.isLoading && appState.recentRepositories.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if appState.recentRepositories.isEmpty {
                Text("No repositories found")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(appState.recentRepositories) { repo in
                        RepositoryRow(repository: repo)
                    }
                }
            }
        }
    }
    
    // App Launchers Section
    private var appLaunchersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quick Launch")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    sheetManager.showSheet(addAppSheetId)
                }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Add custom app")
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 16) {
                // Default apps
                AppLauncherIcon(name: "Cursor", imageName: "cursor", appPath: "/Applications/Cursor.app")
                AppLauncherIcon(name: "Ghostty", imageName: "terminal", appPath: "/Applications/Ghostty.app")
                AppLauncherIcon(name: "Xcode", imageName: "hammer", appPath: "/Applications/Xcode.app")
                AppLauncherIcon(name: "VS Code", imageName: "chevron.left.forwardslash.chevron.right", appPath: "/Applications/Visual Studio Code.app")
                AppLauncherIcon(name: "GitHub", imageName: "person.crop.circle", urlString: "https://github.com")
                
                // Custom apps
                ForEach(appState.customAppLaunchers) { app in
                    AppLauncherIcon(
                        name: app.name,
                        imageName: app.imageName,
                        appPath: app.appPath,
                        urlString: app.urlString,
                        isCustom: true
                    )
                }
            }
        }
    }
}

// Date formatter for contribution data - cached for performance
private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

// Month-year formatter for picker - cached for performance
private let monthYearFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM yyyy"
    return formatter
}()

// Extracts the contribution grid into a separate optimized View
struct ContributionGrid: View {
    let data: [[ContributionDay?]]
    
    var body: some View {
        VStack(spacing: 4) {
            ForEach(data.indices, id: \.self) { weekIndex in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        if let day = data[weekIndex][dayIndex] {
                            ContributionBlock(day: day)
                                .frame(width: 14, height: 14)
                        } else {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 14, height: 14)
                        }
                    }
                }
            }
        }
    }
}

// Component to display a contribution block
struct ContributionBlock: View {
    let day: ContributionDay
    
    var body: some View {
        Rectangle()
            .fill(Color(hex: day.color))
            .cornerRadius(2)
            .help("\(day.count) contributions on \(day.date)")
    }
}

// Updated AddAppView that works with SheetManager
struct ManagedAddAppView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sheetManager: SheetManager
    let sheetId: String
    
    @State private var appName: String = ""
    @State private var appPath: String = ""
    @State private var urlString: String = ""
    @State private var selectedImageName: String = "app"
    @State private var isWebApp: Bool = false
    @State private var showingFilePicker: Bool = false
    
    let systemImages = [
        "app", "terminal", "hammer", "swift", "keyboard", "network", "safari", 
        "pencil", "doc", "folder", "envelope", "calendar", "chart.bar", 
        "camera", "gamecontroller", "music.note", "video", "figure.walk"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Add Custom App")
                .font(.headline)
                .padding(.bottom, 5)
            
            TextField("App Name", text: $appName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Picker("App Type", selection: $isWebApp) {
                Text("Native App").tag(false)
                Text("Web App").tag(true)
            }
            .pickerStyle(SegmentedPickerStyle())
            
            if isWebApp {
                TextField("URL (e.g., https://example.com)", text: $urlString)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            } else {
                HStack {
                    TextField("App Path", text: $appPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("Browse") {
                        showingFilePicker = true
                    }
                    .fileImporter(
                        isPresented: $showingFilePicker,
                        allowedContentTypes: [.application],
                        allowsMultipleSelection: false
                    ) { result in
                        do {
                            let fileURL = try result.get().first!
                            // Capture the file path
                            if fileURL.startAccessingSecurityScopedResource() {
                                appPath = fileURL.path
                                fileURL.stopAccessingSecurityScopedResource()
                            }
                        } catch {
                            print("Failed to get file path: \(error)")
                        }
                    }
                }
            }
            
            Text("Select Icon")
                .font(.subheadline)
            
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 12) {
                    ForEach(systemImages, id: \.self) { imageName in
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedImageName == imageName ? Color.blue.opacity(0.2) : Color.clear)
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: imageName)
                                .font(.system(size: 20))
                                .foregroundColor(selectedImageName == imageName ? .blue : .primary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedImageName = imageName
                        }
                    }
                }
                .padding(.vertical, 5)
            }
            .frame(height: 50)
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    sheetManager.hideSheet(sheetId)
                }
                
                Spacer()
                
                Button("Add") {
                    if !appName.isEmpty && ((!isWebApp && !appPath.isEmpty) || (isWebApp && !urlString.isEmpty)) {
                        let newApp = CustomAppLauncher(
                            name: appName,
                            imageName: selectedImageName,
                            appPath: isWebApp ? nil : appPath,
                            urlString: isWebApp ? urlString : nil
                        )
                        appState.addCustomAppLauncher(newApp)
                        sheetManager.hideSheet(sheetId)
                    }
                }
                .disabled(appName.isEmpty || (isWebApp ? urlString.isEmpty : appPath.isEmpty))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top)
        }
        .padding()
        .withStrongSheet()
    }
}

// Keep the original AddAppView for backward compatibility in other places
struct AddAppView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool
    @State private var appName: String = ""
    @State private var appPath: String = ""
    @State private var urlString: String = ""
    @State private var selectedImageName: String = "app"
    @State private var isWebApp: Bool = false
    @State private var showingFilePicker: Bool = false
    
    let systemImages = [
        "app", "terminal", "hammer", "swift", "keyboard", "network", "safari", 
        "pencil", "doc", "folder", "envelope", "calendar", "chart.bar", 
        "camera", "gamecontroller", "music.note", "video", "figure.walk"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Add Custom App")
                .font(.headline)
                .padding(.bottom, 5)
            
            TextField("App Name", text: $appName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Picker("App Type", selection: $isWebApp) {
                Text("Native App").tag(false)
                Text("Web App").tag(true)
            }
            .pickerStyle(SegmentedPickerStyle())
            
            if isWebApp {
                TextField("URL (e.g., https://example.com)", text: $urlString)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            } else {
                HStack {
                    TextField("App Path", text: $appPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("Browse") {
                        showingFilePicker = true
                    }
                    .fileImporter(
                        isPresented: $showingFilePicker,
                        allowedContentTypes: [.application],
                        allowsMultipleSelection: false
                    ) { result in
                        do {
                            let fileURL = try result.get().first!
                            // Capture the file path
                            if fileURL.startAccessingSecurityScopedResource() {
                                appPath = fileURL.path
                                fileURL.stopAccessingSecurityScopedResource()
                            }
                        } catch {
                            print("Failed to get file path: \(error)")
                        }
                    }
                }
            }
            
            Text("Select Icon")
                .font(.subheadline)
            
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 12) {
                    ForEach(systemImages, id: \.self) { imageName in
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedImageName == imageName ? Color.blue.opacity(0.2) : Color.clear)
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: imageName)
                                .font(.system(size: 20))
                                .foregroundColor(selectedImageName == imageName ? .blue : .primary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedImageName = imageName
                        }
                    }
                }
                .padding(.vertical, 5)
            }
            .frame(height: 50)
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                
                Spacer()
                
                Button("Add") {
                    if !appName.isEmpty && ((!isWebApp && !appPath.isEmpty) || (isWebApp && !urlString.isEmpty)) {
                        let newApp = CustomAppLauncher(
                            name: appName,
                            imageName: selectedImageName,
                            appPath: isWebApp ? nil : appPath,
                            urlString: isWebApp ? urlString : nil
                        )
                        appState.addCustomAppLauncher(newApp)
                        
                        // Force dismiss with a small delay to ensure UI state is updated
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isPresented = false
                        }
                    }
                }
                .disabled(appName.isEmpty || (isWebApp ? urlString.isEmpty : appPath.isEmpty))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top)
        }
        .padding()
        .withStrongSheet()
    }
}

// Setup View
struct SetupView: View {
    @EnvironmentObject private var appState: AppState
    @State private var token: String = ""
    @State private var username: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Personal Dashboard")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Please enter your GitHub credentials to get started")
                .font(.callout)
                .multilineTextAlignment(.center)
            
            TextField("GitHub Username", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            SecureField("GitHub Personal Access Token", text: $token)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            Text("Your token needs repo and user scopes")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Save and Continue") {
                appState.githubToken = token
                appState.username = username
                appState.saveSettings()
            }
            .buttonStyle(.borderedProminent)
            .disabled(token.isEmpty || username.isEmpty)
            .padding(.top)
        }
        .padding()
        .frame(width: 350)
    }
}

// Component to display a repository row
struct RepositoryRow: View {
    let repository: Repository
    
    var body: some View {
        Button(action: {
            if let url = URL(string: repository.html_url) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let description = repository.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    HStack {
                        if let language = repository.language {
                            Circle()
                                .fill(languageColor(language))
                                .frame(width: 8, height: 8)
                            
                            Text(language)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(formatDate(repository.updated_at))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.forward.square")
                    .foregroundColor(.blue)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func languageColor(_ language: String) -> Color {
        switch language.lowercased() {
        case "swift": return Color.orange
        case "python": return Color.blue
        case "javascript": return Color.yellow
        case "typescript": return Color.blue
        case "java": return Color.red
        case "c#": return Color.purple
        case "c++": return Color.pink
        case "html": return Color.orange
        case "css": return Color.blue
        default: return Color.gray
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        
        guard let date = dateFormatter.date(from: dateString) else {
            return "Unknown"
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .short
        return displayFormatter.string(from: date)
    }
}

// App Launcher Icon Component
struct AppLauncherIcon: View {
    @EnvironmentObject private var appState: AppState
    let name: String
    let imageName: String
    let appPath: String?
    let urlString: String?
    let isCustom: Bool
    
    init(name: String, imageName: String, appPath: String) {
        self.name = name
        self.imageName = imageName
        self.appPath = appPath
        self.urlString = nil
        self.isCustom = false
    }
    
    init(name: String, imageName: String, urlString: String) {
        self.name = name
        self.imageName = imageName
        self.appPath = nil
        self.urlString = urlString
        self.isCustom = false
    }
    
    // Init for custom apps that can be removed
    init(name: String, imageName: String, appPath: String?, urlString: String?, isCustom: Bool = true) {
        self.name = name
        self.imageName = imageName
        self.appPath = appPath
        self.urlString = urlString
        self.isCustom = isCustom
    }
    
    var body: some View {
        Button(action: {
            launchApp()
        }) {
            VStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: imageName)
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                
                Text(name)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .modifier(ConditionalContextMenu(isCustom: isCustom) {
            Button(action: {
                // Find and remove this app launcher
                if let index = appState.customAppLaunchers.firstIndex(where: { 
                    $0.name == name && 
                    $0.imageName == imageName && 
                    $0.appPath == appPath && 
                    $0.urlString == urlString 
                }) {
                    appState.removeCustomAppLauncher(at: index)
                }
            }) {
                Label("Remove", systemImage: "trash")
            }
        })
    }
    
    private func launchApp() {
        if let path = appPath {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.open(url)
        } else if let urlString = urlString, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// Helper modifier for conditional context menu
struct ConditionalContextMenu<MenuContent: View>: ViewModifier {
    let isEnabled: Bool
    let menuContent: () -> MenuContent
    
    init(isCustom: Bool, @ViewBuilder menuContent: @escaping () -> MenuContent) {
        self.isEnabled = isCustom
        self.menuContent = menuContent
    }
    
    func body(content: Content) -> some View {
        if isEnabled {
            content.contextMenu {
                menuContent()
            }
        } else {
            content
        }
    }
}

// Model for custom app launchers
struct CustomAppLauncher: Identifiable, Codable {
    let id = UUID()
    let name: String
    let imageName: String
    let appPath: String?
    let urlString: String?
}

// Helper for Color from Hex - optimized version
extension Color {
    static var hexColorCache: [String: Color] = [:]
    
    init(hex: String) {
        // Check if color is already cached
        if let cachedColor = Color.hexColorCache[hex] {
            self = cachedColor
            return
        }
        
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        let color = Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
        
        // Cache the color for future use
        Color.hexColorCache[hex] = color
        self = color
    }
} 