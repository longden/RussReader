import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject private var store: FeedStore
    @AppStorage("rssOnboardingComplete") private var onboardingComplete: Bool = false
    @State private var currentPage = 0
    @State private var selectedFeeds: Set<String> = []
    @State private var articleOpenInPreview = true
    @State private var showUnreadBadge = true
    @State private var refreshInterval = 30
    
    private let totalPages = 4
    
    private let starterFeeds: [SuggestedFeed] = [
        SuggestedFeed(title: "BBC News", url: "https://feeds.bbci.co.uk/news/rss.xml"),
        SuggestedFeed(title: "GitHub Blog", url: "https://github.blog/feed/"),
        SuggestedFeed(title: "Simon Willison", url: "https://simonwillison.net/atom/everything/"),
        SuggestedFeed(title: "Hacking with Swift", url: "https://www.hackingwithswift.com/articles/rss"),
        SuggestedFeed(title: "TechCrunch", url: "https://techcrunch.com/feed/")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Page content
            Group {
                switch currentPage {
                case 0: welcomePage
                case 1: feedsPage
                case 2: filtersPage
                case 3: settingsPage
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Bottom bar
            HStack(spacing: 12) {
                if currentPage > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { currentPage -= 1 }
                    } label: {
                        Text(String(localized: "Back", bundle: .module))
                            .font(.system(size: 12))
                            .frame(width: 60)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                } else {
                    Spacer().frame(width: 60)
                }
                
                Spacer()
                
                // Page indicators
                pageIndicator
                
                Spacer()
                
                if currentPage < totalPages - 1 {
                    nextButton
                } else {
                    getStartedButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: store.windowWidth, height: store.windowHeight)
    }
    
    // MARK: - Navigation Buttons
    
    @ViewBuilder
    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalPages, id: \.self) { page in
                Circle()
                    .fill(page == currentPage ? Color.primary.opacity(0.8) : Color.primary.opacity(0.15))
                    .frame(width: 6, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
    }
    
    @ViewBuilder
    private var nextButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { currentPage += 1 }
        } label: {
            Text(String(localized: "Next", bundle: .module))
                .font(.system(size: 12, weight: .medium))
                .frame(width: 70)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }
    
    @ViewBuilder
    private var getStartedButton: some View {
        Button {
            completeOnboarding()
        } label: {
            Text(String(localized: "Get Started", bundle: .module))
                .font(.system(size: 12, weight: .medium))
                .frame(width: 70)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }
    
    // MARK: - Pages
    
    private var welcomePage: some View {
        VStack(spacing: 14) {
            Spacer()
            
            Image(systemName: "newspaper.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            
            Text(String(localized: "Welcome to RSS Reader", bundle: .module))
                .font(.title2.bold())
            
            Text(String(localized: "A lightweight menu bar reader for staying up to date with your favourite feeds.", bundle: .module))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            
            Spacer()
        }
    }
    
    private var feedsPage: some View {
        VStack(spacing: 10) {
            Spacer()
            
            Text(String(localized: "Pick Some Feeds", bundle: .module))
                .font(.title3.bold())
            
            Text(String(localized: "Select a few to get started.", bundle: .module))
                .font(.callout)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 6) {
                ForEach(starterFeeds) { feed in
                    feedRow(feed)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            
            Text(String(localized: "Add & browse more in Settings → Suggested Feeds", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            
            Spacer()
        }
    }
    
    private var filtersPage: some View {
        VStack(spacing: 14) {
            Spacer()
            
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            
            Text(String(localized: "Smart Filters", bundle: .module))
                .font(.title3.bold())
            
            Text(String(localized: "Set up rules to organise your feed:", bundle: .module))
                .font(.callout)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                filterRow(icon: "bell.badge.fill", color: .blue, text: String(localized: "Get notified about topics you care about", bundle: .module))
                filterRow(icon: "paintbrush.fill", color: .orange, text: String(localized: "Highlight posts with custom colours", bundle: .module))
                filterRow(icon: "eye.slash.fill", color: .red, text: String(localized: "Hide unwanted posts automatically", bundle: .module))
                filterRow(icon: "star.fill", color: .yellow, text: String(localized: "Auto-star items matching your rules", bundle: .module))
            }
            .padding(.horizontal, 36)
            
            Text(String(localized: "Configure in Settings → Filters", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            
            Spacer()
        }
    }
    
    private var settingsPage: some View {
        VStack(spacing: 8) {
            Spacer()
            
            Text(String(localized: "Quick Settings", bundle: .module))
                .font(.title3.bold())
            
            Text(String(localized: "Config to get you started.", bundle: .module))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            
            VStack(spacing: 12) {
                HStack {
                    Text(String(localized: "Article Open", bundle: .module))
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $articleOpenInPreview) {
                        Text(String(localized: "In App Preview", bundle: .module)).tag(true)
                        Text(String(localized: "Open in Browser", bundle: .module)).tag(false)
                    }
                    .frame(width: 170)
                }
                
                HStack {
                    Text(String(localized: "Show unread count in menubar", bundle: .module))
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $showUnreadBadge) {
                        Text(String(localized: "On", bundle: .module)).tag(true)
                        Text(String(localized: "Off", bundle: .module)).tag(false)
                    }
                    .frame(width: 80)
                }
                
                HStack {
                    Text(String(localized: "Refresh Interval", bundle: .module))
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $refreshInterval) {
                        Text(String(localized: "Manual", bundle: .module)).tag(0)
                        Text(String(localized: "15 min", bundle: .module)).tag(15)
                        Text(String(localized: "30 min", bundle: .module)).tag(30)
                        Text(String(localized: "1 hour", bundle: .module)).tag(60)
                    }
                    .frame(width: 120)
                }
                
                HStack {
                    Text(String(localized: "Window Width", bundle: .module))
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $store.windowWidthSize) {
                        Text(String(localized: "Small", bundle: .module)).tag("small")
                        Text(String(localized: "Medium", bundle: .module)).tag("medium")
                        Text(String(localized: "Large", bundle: .module)).tag("large")
                        Text(String(localized: "X-Large", bundle: .module)).tag("xlarge")
                    }
                    .frame(width: 120)
                }
                
                HStack {
                    Text(String(localized: "Window Height", bundle: .module))
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $store.windowHeightSize) {
                        Text(String(localized: "Small", bundle: .module)).tag("small")
                        Text(String(localized: "Medium", bundle: .module)).tag("medium")
                        Text(String(localized: "Large", bundle: .module)).tag("large")
                        Text(String(localized: "X-Large", bundle: .module)).tag("xlarge")
                    }
                    .frame(width: 120)
                }
            }
            .padding(.horizontal, 28)
            
            Text(String(localized: "Advanced configuration available in Settings", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            
            Spacer()
        }
    }
    
    // MARK: - Components
    
    private func feedRow(_ feed: SuggestedFeed) -> some View {
        let isSelected = selectedFeeds.contains(feed.url)
        return Button {
            if isSelected {
                selectedFeeds.remove(feed.url)
            } else {
                selectedFeeds.insert(feed.url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .green : .secondary)
                    .font(.system(size: 16))
                Text(feed.title)
                    .font(.system(size: 13))
                Spacer()
                Text(URL(string: feed.url)?.host ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(isSelected ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
    
    private func filterRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13))
        }
    }
    
    // MARK: - Actions
    
    private func completeOnboarding() {
        let feedsToAdd = starterFeeds.filter { selectedFeeds.contains($0.url) }
        if !feedsToAdd.isEmpty {
            _ = store.addSuggestedFeeds(feedsToAdd)
        }
        
        store.openInPreview = articleOpenInPreview
        store.showUnreadBadge = showUnreadBadge
        store.refreshIntervalMinutes = refreshInterval
        store.startRefreshTimer()
        
        withAnimation(.easeInOut(duration: 0.3)) {
            onboardingComplete = true
        }
    }
}
