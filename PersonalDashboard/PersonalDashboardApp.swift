import SwiftUI
import AppKit

// Class to handle our menu bar functionality
class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var contextMenu: NSMenu?
    
    override init() {
        super.init()
        setupMenus()
    }
    
    func setupMenus() {
        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Set up the icon
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Personal Dashboard")
        }
        
        // Create the context menu (for right-click)
        contextMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApplication.shared
        contextMenu?.addItem(quitItem)
        contextMenu?.delegate = self
        
        // Create popover for main view
        popover = NSPopover()
        popover?.behavior = .transient
        
        // Set the status item's action for right-click
        if let button = statusItem?.button {
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(handleStatusItemClick)
            button.target = self
        }
    }
    
    func setContentView<T: View>(_ view: T) {
        popover?.contentSize = NSSize(width: 450, height: 550)
        popover?.contentViewController = NSHostingController(rootView: view)
    }
    
    @objc func handleStatusItemClick(sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        
        if event?.type == .rightMouseUp {
            // Show context menu on right-click
            if let contextMenu = contextMenu {
                statusItem?.popUpMenu(contextMenu)
            }
        } else {
            // For left-click, show the popover with our SwiftUI view
            if let popover = popover, let button = statusItem?.button {
                if popover.isShown {
                    popover.performClose(nil)
                } else {
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
                    
                    // Keep popover active when clicking inside it
                    if let popoverWindow = popover.contentViewController?.view.window {
                        popoverWindow.makeKey()
                    }
                }
            }
        }
    }
    
    // This method is required by NSMenuDelegate to validate menu items
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Make sure all menu items are enabled
        for item in menu.items {
            item.isEnabled = true
        }
    }
}

@main
struct PersonalDashboardApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up our custom menu bar controller
        MenuBarController.shared.setContentView(
            ContentView().environmentObject(appState)
        )
        
        // Hide dock icon
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

class AppState: ObservableObject {
    @Published var githubToken: String = UserDefaults.standard.string(forKey: "githubToken") ?? ""
    @Published var username: String = UserDefaults.standard.string(forKey: "githubUsername") ?? ""
    @Published var recentRepositories: [Repository] = []
    @Published var contributionData: [ContributionDay] = []
    @Published var isLoading: Bool = false
    @Published var customAppLaunchers: [CustomAppLauncher] = []
    
    // Cache expiration timestamps
    private var repoCacheTimestamp: Date?
    private var contributionCacheTimestamp: Date?
    
    // URLSession for network requests
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()
    
    init() {
        loadCustomAppLaunchers()
        loadCachedData()
    }
    
    func saveSettings() {
        UserDefaults.standard.set(githubToken, forKey: "githubToken")
        UserDefaults.standard.set(username, forKey: "githubUsername")
        fetchGitHubData(forceRefresh: true)
    }
    
    func fetchGitHubData(forceRefresh: Bool = false) {
        guard !githubToken.isEmpty, !username.isEmpty else { return }
        
        let shouldRefreshRepos = forceRefresh || repoCacheTimestamp == nil || 
            Calendar.current.date(byAdding: .minute, value: 30, to: repoCacheTimestamp!)! < Date()
        
        let shouldRefreshContributions = forceRefresh || contributionCacheTimestamp == nil || 
            Calendar.current.date(byAdding: .hour, value: 6, to: contributionCacheTimestamp!)! < Date()
        
        if !shouldRefreshRepos && !shouldRefreshContributions {
            return
        }
        
        isLoading = true
        
        let group = DispatchGroup()
        
        // Fetch recent repositories
        if shouldRefreshRepos {
            group.enter()
            fetchRecentRepositories {
                group.leave()
            }
        }
        
        // Fetch contribution data
        if shouldRefreshContributions {
            group.enter()
            fetchContributionData {
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.isLoading = false
            self?.saveCachedData()
        }
    }
    
    // MARK: - Custom App Launchers Functions
    
    func addCustomAppLauncher(_ appLauncher: CustomAppLauncher) {
        customAppLaunchers.append(appLauncher)
        saveCustomAppLaunchers()
    }
    
    func removeCustomAppLauncher(at index: Int) {
        if index < customAppLaunchers.count {
            customAppLaunchers.remove(at: index)
            saveCustomAppLaunchers()
        }
    }
    
    private func saveCustomAppLaunchers() {
        if let encoded = try? JSONEncoder().encode(customAppLaunchers) {
            UserDefaults.standard.set(encoded, forKey: "customAppLaunchers")
        }
    }
    
    private func loadCustomAppLaunchers() {
        if let savedApps = UserDefaults.standard.data(forKey: "customAppLaunchers"),
           let decodedApps = try? JSONDecoder().decode([CustomAppLauncher].self, from: savedApps) {
            customAppLaunchers = decodedApps
        }
    }
    
    // MARK: - Cache Management
    
    private func saveCachedData() {
        if !recentRepositories.isEmpty {
            if let encoded = try? JSONEncoder().encode(recentRepositories) {
                UserDefaults.standard.set(encoded, forKey: "cachedRepositories")
                repoCacheTimestamp = Date()
                UserDefaults.standard.set(repoCacheTimestamp, forKey: "repoCacheTimestamp")
            }
        }
        
        if !contributionData.isEmpty {
            if let encoded = try? JSONEncoder().encode(contributionData) {
                UserDefaults.standard.set(encoded, forKey: "cachedContributions")
                contributionCacheTimestamp = Date()
                UserDefaults.standard.set(contributionCacheTimestamp, forKey: "contributionCacheTimestamp")
            }
        }
    }
    
    private func loadCachedData() {
        repoCacheTimestamp = UserDefaults.standard.object(forKey: "repoCacheTimestamp") as? Date
        contributionCacheTimestamp = UserDefaults.standard.object(forKey: "contributionCacheTimestamp") as? Date
        
        if let savedRepos = UserDefaults.standard.data(forKey: "cachedRepositories"),
           let decodedRepos = try? JSONDecoder().decode([Repository].self, from: savedRepos) {
            recentRepositories = decodedRepos
        }
        
        if let savedContributions = UserDefaults.standard.data(forKey: "cachedContributions"),
           let decodedContributions = try? JSONDecoder().decode([ContributionDay].self, from: savedContributions) {
            contributionData = decodedContributions
        }
    }
    
    private func fetchRecentRepositories(completion: @escaping () -> Void) {
        guard let url = URL(string: "https://api.github.com/users/\(username)/repos?sort=updated&per_page=5") else {
            completion()
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    completion()
                }
                return
            }
            
            do {
                let repositories = try JSONDecoder().decode([Repository].self, from: data)
                DispatchQueue.main.async {
                    self?.recentRepositories = repositories
                    self?.repoCacheTimestamp = Date()
                    completion()
                }
            } catch {
                print("Error decoding repositories: \(error)")
                DispatchQueue.main.async {
                    completion()
                }
            }
        }.resume()
    }
    
    private func fetchContributionData(completion: @escaping () -> Void) {
        guard let url = URL(string: "https://api.github.com/graphql") else { 
            completion()
            return
        }
        
        let query = """
        {
          user(login: "\(username)") {
            contributionsCollection {
              contributionCalendar {
                weeks {
                  contributionDays {
                    date
                    contributionCount
                    color
                  }
                }
              }
            }
          }
        }
        """
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        let body: [String: Any] = ["query": query]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    completion()
                }
                return
            }
            
            // Process the GraphQL response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let data = json["data"] as? [String: Any],
               let user = data["user"] as? [String: Any],
               let contributionsCollection = user["contributionsCollection"] as? [String: Any],
               let contributionCalendar = contributionsCollection["contributionCalendar"] as? [String: Any],
               let weeks = contributionCalendar["weeks"] as? [[String: Any]] {
                
                var contributions: [ContributionDay] = []
                
                for week in weeks {
                    if let days = week["contributionDays"] as? [[String: Any]] {
                        for day in days {
                            if let date = day["date"] as? String,
                               let count = day["contributionCount"] as? Int,
                               let color = day["color"] as? String {
                                contributions.append(ContributionDay(date: date, count: count, color: color))
                            }
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self?.contributionData = contributions
                    self?.contributionCacheTimestamp = Date()
                    completion()
                }
            } else {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }.resume()
    }
}

struct Repository: Codable, Identifiable {
    let id: Int
    let name: String
    let full_name: String
    let html_url: String
    let description: String?
    let language: String?
    let updated_at: String
}

struct ContributionDay: Codable, Identifiable, Equatable {
    let id = UUID()
    let date: String
    let count: Int
    let color: String
    
    enum CodingKeys: String, CodingKey {
        case date, count, color
    }
    
    init(date: String, count: Int, color: String) {
        self.date = date
        self.count = count
        self.color = color
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        count = try container.decode(Int.self, forKey: .count)
        color = try container.decode(String.self, forKey: .color)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(count, forKey: .count)
        try container.encode(color, forKey: .color)
    }
    
    // Implement Equatable
    static func == (lhs: ContributionDay, rhs: ContributionDay) -> Bool {
        return lhs.date == rhs.date && 
               lhs.count == rhs.count && 
               lhs.color == rhs.color
    }
} 