import SwiftUI
import Photos
import PhotosUI   // presentLimitedLibraryPicker lives here, not in Photos


/// Streams how far a scroll view is over-pulled past its top (0 when not).
/// iOS 18+ only — on 17 the gesture is simply unavailable.
private struct PullToReveal: ViewModifier {
    @Binding var pull: CGFloat
    let onChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                max(0, -(geo.contentOffset.y + geo.contentInsets.top))
            } action: { _, overpull in
                pull = overpull
                onChange(overpull)
            }
        } else {
            content
        }
    }
}

/// Branded pre-access onboarding — sets the app's identity and asks for Photos.
struct OnboardingView: View {
    let onAuthorized: () -> Void
    @State private var requesting = false

    /// Already denied/restricted? iOS won't re-prompt, so the primary button must
    /// send the user to Settings instead of calling the (no-op) authorization
    /// request again. Re-evaluated on every body pass (e.g. on foreground return).
    private var isDenied: Bool {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return s == .denied || s == .restricted
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            LumenGlyph(size: 84)
            Text("Lumen").font(.system(size: 38, weight: .heavy, design: .rounded)).foregroundStyle(.white).padding(.top, 18)
            Text("사진 정리가 쉬워집니다").font(.headline).foregroundStyle(.white.opacity(0.6)).padding(.top, 4)

            VStack(spacing: 18) {
                feature("hand.draw.fill", "넘기며 둘러보기", "좌우로 넘기고, 위로 올리면 삭제 후보")
                feature("tray.full.fill", "보관은 Lumen 앨범에", "보관함에 담은 사진을 한 곳에 모아 나중에 분류")
                feature("checkmark.shield.fill", "안전하게", "삭제는 항상 확인 후 진행")
            }
            .padding(.top, 36).padding(.horizontal, 30)

            Spacer()
            Button {
                if isDenied {
                    openSettings()   // can't re-prompt; bounce to Settings
                } else {
                    requesting = true
                    Task { onAuthorized(); requesting = false }
                }
            } label: {
                Text(isDenied ? "설정에서 사진 접근 허용" : "사진 접근 허용").font(.headline)
                    .opacity(requesting ? 0 : 1)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .overlay { if requesting { ProgressView().tint(.white) } }
            }
            .background(heroGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
            .padding(.horizontal, 24).padding(.bottom, 18)
            // When denied, the Settings path IS the primary button — show a hint
            // line instead of a redundant second button.
            if isDenied {
                Text("설정 ▸ Lumen ▸ 사진에서 ‘전체 액세스’를 선택하세요")
                    .font(.footnote).foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center).padding(.horizontal, 30).padding(.bottom, 24)
            } else {
                Color.clear.frame(height: 1).padding(.bottom, 24)
            }
        }
    }

    // LocalizedStringKey params so the literal call-site strings localize.
    private func feature(_ icon: String, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.title2).foregroundStyle(.tint).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(subtitle).font(.footnote).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
    }
}

struct OrganizePickerView: View {
    let library: PhotoLibrary
    var scrollTopKey: Int = 0   // tab re-tap: pop the open album, else scroll to top
    @State private var scope: OrganizeScope?
    @State private var resume: ResumeTarget?
    @State private var showSettings = false
    @State private var pull: CGFloat = 0      // current over-pull past the list top
    @State private var pullArmed = true       // one settings open per pull
    @AppStorage("lumen.lastOrganizedScopeId") private var lastScopeId = "all"

    /// How far past the top you pull before settings open — deliberately long
    /// (~2x a refresh pull) so casual bounces never trigger it.
    private static let settingsPullThreshold: CGFloat = 160

    /// The album + position the user last organized, if it's still meaningful.
    private var resumeTarget: ResumeTarget? {
        guard let s = library.scopes.first(where: { $0.id == lastScopeId }) else { return nil }
        let i = UserDefaults.standard.integer(forKey: "lumen.resume.\(s.id)")
        guard i > 0, i < s.count - 1 else { return nil }
        return ResumeTarget(scope: s, index: i)
    }

    var body: some View {
        ScrollViewReader { proxy in
        ZStack {
            ZStack {
                Color.lumenBG.ignoresSafeArea()
                if !library.loaded {
                    ProgressView().tint(.white.opacity(0.4))
                } else if library.scopes.isEmpty {
                    organizeEmptyState
                } else {
                    pickerList
                }
            }
            // Pinned tab title — same style as every other tab.
            .overlay(alignment: .top) { TabTitleBar(title: String(localized: "정리")) }
            .offset(x: scope != nil ? -UIScreen.main.bounds.width * 0.22 : 0)
            .overlay(Color.black.opacity(scope != nil ? 0.25 : 0).ignoresSafeArea())

            // Album opens as a browsing grid first — tap a photo to view it, then
            // "정리 시작" begins organizing from that photo (not from the start).
            if let s = scope {
                AlbumGalleryView(scope: s, library: library,
                                 onClose: { withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) { scope = nil } })
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .preferredColorScheme(.dark)
        .tint(.lumenAccent)
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .fullScreenCover(item: $resume) { r in
            // Straight to the saved spot — already in organize mode.
            OrganizeView(scope: r.scope, library: library, startIndex: r.index)
        }
        // Tab re-tap: an open album pops back to the picker; the picker scrolls to top.
        .onChange(of: scrollTopKey) {
            if scope != nil {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) { scope = nil }
            } else {
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("organize-top", anchor: .top) }
            }
        }
        }
    }

    /// Empty state — distinguishes "no photos" from the .limited case, where the
    /// fix is to grant access to more photos (the system picker), not to add any.
    private var organizeEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: library.limited ? "photo.on.rectangle.angled" : "sparkles")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.white.opacity(0.22))
            Text(library.limited ? String(localized: "선택된 사진이 없어요") : String(localized: "정리할 사진이 없어요"))
                .font(.subheadline).foregroundStyle(.white.opacity(0.5))
            if library.limited {
                Button { Self.presentLimitedLibraryPicker() } label: {
                    Text("사진 더 선택하기")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(.white.opacity(0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
                }
                .buttonStyle(.plain).padding(.top, 4)
            }
        }
    }

    /// .limited: a quiet card above the album list — offers the system "add more
    /// photos" sheet so a small library doesn't look broken.
    private var limitedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title3).foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 2) {
                Text("일부 사진만 보고 있어요")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text("전체 허용은 설정 앱에서 바꿀 수 있어요")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 8)
            Button { Self.presentLimitedLibraryPicker() } label: {
                Text("더 선택하기")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 13).padding(.vertical, 7)
                    .background(.white.opacity(0.1), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.07)))
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    /// System sheet that lets a .limited user add/remove visible photos.
    static func presentLimitedLibraryPicker() {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?.rootViewController
        guard let root else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }

    private func handlePull(_ y: CGFloat) {
        if y > Self.settingsPullThreshold, pullArmed, !showSettings {
            pullArmed = false
            showSettings = true
        } else if y < 5 {
            pullArmed = true     // re-arm once the bounce settles
        }
    }

    private var pickerList: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 안내 한 줄 — 타이틀은 핀(TabTitleBar)으로 올라갔다.
                Text("앨범을 골라보세요 · 위로 올리면 삭제 · 정리가 끝나면 한번에 삭제")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                    .id("organize-top")

                if library.limited { limitedBanner }

                // 이어서 정리 — 마지막으로 보던 앨범·위치로 바로 점프.
                if let r = resumeTarget {
                    Button { resume = r } label: { ResumeCard(target: r, library: library) }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16).padding(.bottom, 12)
                }

                // 리스트
                VStack(spacing: 0) {
                    ForEach(Array(library.scopes.enumerated()), id: \.element.id) { i, s in
                        ScopeRow(scope: s, library: library)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) { scope = s }
                                library.prewarmScope(s)
                            }
                        if i < library.scopes.count - 1 {
                            Divider().overlay(.white.opacity(0.07))
                        }
                    }
                }
                .background(Color.lumenCard)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.06)))
                .padding(.horizontal, 16)
            }
        }
        .contentMargins(.top, 52, for: .scrollContent)   // start below the pinned title
        .scrollBounceBehavior(.always, axes: .vertical)
        .modifier(PullToReveal(pull: $pull) { handlePull($0) })
        // Hidden settings: pull the list down past the threshold and the sheet opens
        // (with a haptic). A gear rides in with the pull so it's discoverable.
        .overlay(alignment: .top) {
            let p = min(pull / Self.settingsPullThreshold, 1)
            if p > 0.02 {
                Image(systemName: "gearshape.fill")
                    .font(.title3).foregroundStyle(.white.opacity(0.85))
                    .rotationEffect(.degrees(Double(pull) * 1.5))
                    .opacity(Double(p)).scaleEffect(0.5 + 0.5 * p)
                    .offset(y: 38 + pull * 0.45)
            }
        }
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: showSettings) { _, new in new }
    }
}

/// Where the user left off — drives the 정리 탭's "이어서 정리" card.
struct ResumeTarget: Identifiable {
    var id: String { scope.id }
    let scope: OrganizeScope
    let index: Int
}

/// The 정리 탭's hero card: jump back to where organizing left off.
private struct ResumeCard: View {
    let target: ResumeTarget
    let library: PhotoLibrary
    @State private var cover: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Color.white.opacity(0.06)
                if let cover {
                    Image(uiImage: cover).resizable().scaledToFill()
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("이어서 정리").font(.body.weight(.semibold)).foregroundStyle(.white)
                Text("\(target.scope.title) · \(target.index + 1)번째 사진부터")
                    .font(.caption).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Image(systemName: "arrow.forward.circle.fill")
                .font(.title3).foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.lumenCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.06)))
        .contentShape(Rectangle())
        .task(id: target.scope.cover?.localIdentifier) {
            if let a = target.scope.cover {
                for await img in library.imageStream(a, points: 52, mode: .aspectFill) { cover = img }
            }
        }
    }
}

private struct ScopeRow: View {
    let scope: OrganizeScope
    let library: PhotoLibrary
    @State private var cover: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            // 썸네일
            ZStack {
                Color.white.opacity(0.06)
                if let cover {
                    Image(uiImage: cover).resizable().scaledToFill()
                } else {
                    Image(systemName: scope.symbol)
                        .font(.system(size: 16)).foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(scope.title)
                    .font(.body.weight(.semibold)).foregroundStyle(.white)
                Text("\(scope.count)장")
                    .font(.caption).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
        .task(id: scope.cover?.localIdentifier) {
            if let a = scope.cover {
                for await img in library.imageStream(a, points: 52, mode: .aspectFill) { cover = img }
            }
        }
    }
}
