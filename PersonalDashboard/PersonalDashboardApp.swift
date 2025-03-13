import SwiftUI

@main
struct PersonalDashboardApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra("Personal Dashboard", systemImage: "terminal") {
            ContentView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

class AppState: ObservableObject {
    @Published var githubToken: String = UserDefaults.standard.string(forKey: "githubToken") ?? ""
    @Published var username: String = UserDefaults.standard.string(forKey: "githubUsername") ?? ""
    @Published var recentRepositories: [Repository] = []
    @Published var contributionData: [ContributionDay] = []
    @Published var isLoading: Bool = false
    @Published var customAppLaunchers: [CustomAppLauncher] = []
    
    init() {
        loadCustomAppLaunchers()
    }
    
    func saveSettings() {
        UserDefaults.standard.set(githubToken, forKey: "githubToken")
        UserDefaults.standard.set(username, forKey: "githubUsername")
        fetchGitHubData()
    }
    
    func fetchGitHubData() {
        guard !githubToken.isEmpty, !username.isEmpty else { return }
        
        isLoading = true
        
        // Fetch recent repositories
        fetchRecentRepositories()
        
        // Fetch contribution data
        fetchContributionData()
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
    
    private func fetchRecentRepositories() {
        guard let url = URL(string: "https://api.github.com/users/\(username)/repos?sort=updated&per_page=5") else { return }
        
        var request = URLRequest(url: url)
        request.addValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
                return
            }
            
            do {
                let repositories = try JSONDecoder().decode([Repository].self, from: data)
                DispatchQueue.main.async {
                    self?.recentRepositories = repositories
                    self?.isLoading = false
                }
            } catch {
                print("Error decoding repositories: \(error)")
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
            }
        }.resume()
    }
    
    private func fetchContributionData() {
        // This requires a GraphQL query to GitHub's API
        guard let url = URL(string: "https://api.github.com/graphql") else { return }
        
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
        
        let body: [String: Any] = ["query": query]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self?.isLoading = false
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
                    self?.isLoading = false
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

struct ContributionDay: Identifiable {
    let id = UUID()
    let date: String
    let count: Int
    let color: String
} 