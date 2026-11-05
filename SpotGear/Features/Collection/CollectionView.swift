import SwiftData
import SwiftUI

struct CollectionView: View {
    let actions: AddPhotoActions

    @Query(sort: \Spot.createdAt, order: .reverse) private var spots: [Spot]
    @State private var searchText = ""
    @State private var favoritesOnly = false
    @State private var reward: GarageReward?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var filteredSpots: [Spot] {
        spots.filter { spot in
            (!favoritesOnly || spot.isFavorite) && spot.matches(search: searchText)
        }
    }

    private var progress: GarageProgress {
        GarageProgress(spots: spots.map(\.facts))
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 160), spacing: Spacing.medium, alignment: .top)]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.large) {
                GarageHeaderView(progress: progress)
                content
                    .padding(.horizontal)
            }
            .padding(.bottom, Spacing.large)
        }
        .background(Theme.night.ignoresSafeArea())
        .navigationTitle("Collection")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search make or model"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: AppRoute.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Toggle(isOn: $favoritesOnly) {
                    Label("Favorites Only", systemImage: favoritesOnly ? "heart.fill" : "heart")
                }
                .toggleStyle(.button)
                .accessibilityIdentifier("collection.favoritesOnly")
                AddPhotoMenu(actions: actions) {
                    Label("Add Photo", systemImage: "plus")
                }
            }
        }
        .overlay(alignment: .top) {
            if let reward {
                GarageRewardBanner(reward: reward)
                    .padding(.top, Spacing.medium)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: progress) { old, new in
            guard new.xp > old.xp else { return }
            showReward(GarageReward(xp: new.xp - old.xp, newLevel: new.level > old.level ? new.level : nil))
        }
        .task(id: reward) {
            guard reward != nil else { return }
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation { reward = nil }
        }
        .sensoryFeedback(.success, trigger: reward) { _, new in new != nil }
    }

    private func showReward(_ newReward: GarageReward) {
        withAnimation { reward = newReward }
        AccessibilityNotification.Announcement(newReward.announcement).post()
    }

    @ViewBuilder
    private var content: some View {
        if spots.isEmpty {
            PixelEmptyState(
                title: "Your Garage Starts Here",
                message: "Take a photo or choose one from your library. You can collect multiple cars from a single photo."
            ) {
                AddPhotoMenu(actions: actions) {
                    Text("Add Photo")
                }
                .buttonStyle(PixelButtonStyle())
            }
        } else if filteredSpots.isEmpty {
            if searchText.isEmpty {
                PixelEmptyState(
                    title: "No Favorites Yet",
                    message: "Open a car's details to add it to your favorites.",
                    art: .heartEmpty
                )
            } else {
                PixelEmptyState(
                    title: "No Results",
                    message: "Try a different make or model."
                )
            }
        } else {
            LazyVGrid(columns: columns, spacing: Spacing.large) {
                ForEach(filteredSpots) { spot in
                    NavigationLink(value: AppRoute.spot(spot.id)) {
                        SpotCardView(spot: spot)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
