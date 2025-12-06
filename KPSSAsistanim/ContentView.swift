import SwiftUI
import Combine
import UserNotifications
import Charts
import PhotosUI

let YOUTUBE_API_KEY = "API here!"


// YouTube API Modelleri
struct YouTubePlaylistResponse: Codable {
    let items: [PlaylistItem]
    let nextPageToken: String?
}

struct PlaylistItem: Codable {
    let snippet: Snippet
}

struct Snippet: Codable {
    let title: String
    let resourceId: ResourceId
    let thumbnails: Thumbnails?
}

struct ResourceId: Codable {
    let videoId: String
}

struct Thumbnails: Codable {
    let medium: ThumbnailInfo?
    let high: ThumbnailInfo?
}

struct ThumbnailInfo: Codable {
    let url: String
}

// Uygulama Modelleri
struct UserProfile: Codable {
    var name: String
    var surname: String
    var department: String
    var examDate: Date
    var avatarSelection: String
    var customImageData: Data?
}

struct Subject: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var category: String
    var isCompleted: Bool
    var note: String?
    var scheduledDate: Date?
    var hasNotification: Bool
}

struct VideoLesson: Identifiable, Codable {
    var id = UUID()
    var title: String
    var subject: String
    var durationString: String
    var isWatched: Bool
    var youtubeId: String
    var thumbnailUrl: String
}

struct Flashcard: Identifiable, Codable {
    var id = UUID()
    var statement: String
    var isStatementCorrect: Bool
    var explanation: String
    var category: String
}

struct FlashcardResult {
    var correctCount: Int = 0
    var incorrectCount: Int = 0
    var wrongCards: [Flashcard] = []
    var totalCards: Int = 0
}

struct SubjectStat: Identifiable {
    let id = UUID()
    let category: String
    let type: String
    let count: Int
}

// MARK: - 2. VIEW MODEL

class StudyViewModel: ObservableObject {
    @Published var userProfile: UserProfile?
    @Published var isOnboardingCompleted: Bool = false
    
    @Published var subjects: [Subject] = [] { didSet { saveSubjects() } }
    @Published var videos: [VideoLesson] = [] { didSet { saveVideos() } }
    
    @Published var flashcards: [Flashcard] = []
    @Published var activeFlashcards: [Flashcard] = []
    @Published var sessionResult = FlashcardResult()
    @Published var isSessionFinished = false
    
    @Published var isFetchingVideos = false
    @Published var fetchError: String? = nil
    
    let cuteAvatars = ["👩‍🎓", "👨‍🏫", "🤓", "🚀", "🧠"]
    let departments = [
        "Sınıf Öğretmenliği", "Okul Öncesi", "Özel Eğitim", "Türkçe Öğrt.", "DKAB",
        "PDR", "Hukuk", "İktisat", "İşletme", "Maliye", "Kamu Yön.",
        "Hemşirelik", "Ebelik", "Mühendislik", "Mimarlık", "Sosyal Hizmet",
        "Tıbbi Sekreterlik", "Adalet", "Diğer"
    ]
    
    init() {
    
        
        loadData()
        
      
        if flashcards.isEmpty {
            loadFlashcards()
        } else {
            resetSession()
        }
        
        requestNotificationPermission()
    }
    

    func resetForPrototype() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        self.userProfile = nil
        self.isOnboardingCompleted = false
        self.subjects = []
        self.videos = []
    }
    
    // --- KULLANICI ---
    func updateUser(name: String, surname: String, department: String, date: Date, avatar: String, imageData: Data?) {
        let profile = UserProfile(name: name, surname: surname, department: department, examDate: date, avatarSelection: avatar, customImageData: imageData)
        self.userProfile = profile
        withAnimation { self.isOnboardingCompleted = true }
    }
    
    // --- KONU ---
    func addSubject(name: String, category: String, note: String, date: Date, hasNotification: Bool) {
        let newSubject = Subject(name: name, category: category, isCompleted: false, note: note.isEmpty ? nil : note, scheduledDate: date, hasNotification: hasNotification)
        withAnimation { subjects.append(newSubject) }
        if hasNotification { scheduleSpecificNotification(for: newSubject) }
    }
    
    func deleteSubject(_ subject: Subject) {
        if let index = subjects.firstIndex(of: subject) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [subject.id.uuidString])
            _ = withAnimation { subjects.remove(at: index) }
        }
    }
    
    func toggleSubject(_ subject: Subject) {
        if let index = subjects.firstIndex(where: { $0.id == subject.id }) {
            _ = withAnimation { subjects[index].isCompleted.toggle() }
        }
    }
    
    // --- VİDEO YÖNETİMİ ---
    
    func toggleVideo(_ video: VideoLesson) {
        if let index = videos.firstIndex(where: { $0.id == video.id }) {
            _ = withAnimation { videos[index].isWatched.toggle() }
        }
    }
    
    func removePlaylist(subjectName: String) {
        _ = withAnimation { videos.removeAll { $0.subject == subjectName } }
    }
    
    //YOUTUBE API FONKSİYONU
    func fetchRealYouTubePlaylist(subjectName: String, playlistLink: String, pageToken: String? = nil) {
        self.isFetchingVideos = true
        self.fetchError = nil
        
        var playlistID = ""
        if let range = playlistLink.range(of: "list=") {
            let idPart = playlistLink[range.upperBound...]
            if let endRange = idPart.range(of: "&") {
                playlistID = String(idPart[..<endRange.lowerBound])
            } else {
                playlistID = String(idPart)
            }
        } else {
            playlistID = playlistLink
        }
        
        var urlString = "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&maxResults=50&playlistId=\(playlistID)&key=\(YOUTUBE_API_KEY)"
        if let token = pageToken {
            urlString += "&pageToken=\(token)"
        }
        
        guard let url = URL(string: urlString) else {
            self.fetchError = "Link formatı hatalı."
            self.isFetchingVideos = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let _ = error {
                    self.fetchError = "İnternet hatası."
                    self.isFetchingVideos = false
                    return
                }
                
                guard let data = data else { return }
                
                do {
                    let decodedResponse = try JSONDecoder().decode(YouTubePlaylistResponse.self, from: data)
                    
                    var newVideos: [VideoLesson] = []
                    
                    for item in decodedResponse.items {
                        let title = item.snippet.title
                        if title == "Private video" || title == "Deleted video" { continue }
                        
                        let videoId = item.snippet.resourceId.videoId
                        let thumb = item.snippet.thumbnails?.medium?.url ?? ""
                        
                        newVideos.append(VideoLesson(
                            title: title,
                            subject: subjectName,
                            durationString: "YouTube",
                            isWatched: false,
                            youtubeId: videoId,
                            thumbnailUrl: thumb
                        ))
                    }
                    
                    if pageToken == nil {
                        _ = withAnimation {
                            self.videos.removeAll { $0.subject == subjectName }
                        }
                    }
                    
                    _ = withAnimation {
                        self.videos.append(contentsOf: newVideos)
                    }
                    
                    if let nextToken = decodedResponse.nextPageToken {
                        self.fetchRealYouTubePlaylist(subjectName: subjectName, playlistLink: playlistLink, pageToken: nextToken)
                    } else {
                        self.isFetchingVideos = false
                    }
                    
                } catch {
                    print("JSON Hata: \(error)")
                    self.fetchError = "Veri alınamadı. Playlist gizli veya link hatalı olabilir."
                    self.isFetchingVideos = false
                }
            }
        }.resume()
    }
    
    // --- KARTLAR ---
    func loadFlashcards() {
        self.flashcards = [
            Flashcard(statement: "Türkiye'nin en uzun kıyı şeridi Akdeniz'dedir.", isStatementCorrect: false, explanation: "Yanlış. Girinti-çıkıntı nedeniyle Ege'dir.", category: "Coğrafya"),
            Flashcard(statement: "Atatürk'ün nüfusu Gaziantep'e kayıtlıdır.", isStatementCorrect: true, explanation: "Doğru. Şahinbey nüfusuna kayıtlıdır.", category: "Tarih"),
            Flashcard(statement: "TBMM'nin açılışı 1923'tür.", isStatementCorrect: false, explanation: "Yanlış. 23 Nisan 1920'dir.", category: "Tarih"),
            Flashcard(statement: "Yüksek Seçim Kurulu kararlarına itiraz edilemez.", isStatementCorrect: true, explanation: "Doğru. YSK kararları kesindir.", category: "Vatandaşlık"),
            Flashcard(statement: "Türkiye'nin en büyük gölü Tuz Gölü'dür.", isStatementCorrect: false, explanation: "Yanlış. Van Gölü'dür.", category: "Coğrafya")
        ].shuffled()
        resetSession()
    }
    
    func resetSession() {
        self.activeFlashcards = self.flashcards.shuffled()
        self.sessionResult = FlashcardResult(totalCards: self.activeFlashcards.count)
        self.isSessionFinished = false
    }
    
    func processCardSwipe(card: Flashcard, userSwipedRight: Bool) {
        if userSwipedRight == card.isStatementCorrect {
            sessionResult.correctCount += 1
        } else {
            sessionResult.incorrectCount += 1
            sessionResult.wrongCards.append(card)
        }
        _ = withAnimation { activeFlashcards.removeAll(where: { $0.id == card.id }) }
        if activeFlashcards.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.isSessionFinished = true } }
    }
    
    // --- DİĞER ---
    func requestNotificationPermission() { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in } }
    
    func scheduleSpecificNotification(for subject: Subject) {
        guard let d = subject.scheduledDate else { return }
        let content = UNMutableNotificationContent()
        content.title = "Ders Vakti!"; content.body = "\(subject.name) çalışman lazım."
        let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: d.addingTimeInterval(-3600))
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: subject.id.uuidString, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
    
    func saveSubjects() { if let e = try? JSONEncoder().encode(subjects) { UserDefaults.standard.set(e, forKey: "SavedSubjects") } }
    func saveVideos() { if let e = try? JSONEncoder().encode(videos) { UserDefaults.standard.set(e, forKey: "SavedVideos") } }
    
    func loadData() {
        self.isOnboardingCompleted = UserDefaults.standard.bool(forKey: "IsOnboardingCompleted")
        if let d = UserDefaults.standard.data(forKey: "UserProfile"), let p = try? JSONDecoder().decode(UserProfile.self, from: d) { self.userProfile = p }
        if let d = UserDefaults.standard.data(forKey: "SavedSubjects"), let s = try? JSONDecoder().decode([Subject].self, from: d) { self.subjects = s }
        if let d = UserDefaults.standard.data(forKey: "SavedVideos"), let v = try? JSONDecoder().decode([VideoLesson].self, from: d) { self.videos = v }
    }
    
    var totalProgress: Double { subjects.isEmpty ? 0 : Double(subjects.filter{$0.isCompleted}.count) / Double(subjects.count) }
    
    var videoProgress: Double {
        videos.isEmpty ? 0 : Double(videos.filter{$0.isWatched}.count) / Double(videos.count)
    }
    
    func progress(for cat: String) -> Double {
        let c = subjects.filter { $0.category == cat }
        return c.isEmpty ? 0 : Double(c.filter{$0.isCompleted}.count) / Double(c.count)
    }
    
    func getSubjectStats() -> [SubjectStat] {
        let categories = ["Türkçe", "Matematik", "Tarih", "Coğrafya", "Vatandaşlık", "Eğitim"]
        var stats: [SubjectStat] = []
        for cat in categories {
            let total = subjects.filter { $0.category == cat }.count
            if total > 0 {
                let done = subjects.filter { $0.category == cat && $0.isCompleted }.count
                stats.append(SubjectStat(category: cat, type: "Tamamlanan", count: done))
                stats.append(SubjectStat(category: cat, type: "Toplam", count: total))
            }
        }
        return stats
    }
}

// MARK: - 3. UYGULAMA GİRİŞİ

@main
struct KPSSApp: App {
    @StateObject var viewModel = StudyViewModel()
    @State private var isActive = false
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isActive {
                    if viewModel.isOnboardingCompleted {
                        ContentView()
                            .environmentObject(viewModel)
                            .environment(\.locale, Locale(identifier: "tr_TR"))
                            .preferredColorScheme(.light)
                    } else {
                        OnboardingView()
                            .environmentObject(viewModel)
                            .environment(\.locale, Locale(identifier: "tr_TR"))
                            .preferredColorScheme(.light)
                    }
                } else {
                    SplashScreenView()
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { self.isActive = true }
                }
            }
        }
    }
}

// MARK: - 4. SPLASH SCREEN

struct SplashScreenView: View {
    @State private var size = 0.8
    @State private var opacity = 0.5
    
    var body: some View {
        VStack {
            VStack {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250, height: 250)
                    
                
            }
            .scaleEffect(size)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeIn(duration: 1.2)) {
                    self.size = 0.9
                    self.opacity = 1.00
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

// MARK: - 5. ONBOARDING & CONTENTVIEW

struct OnboardingView: View {
    @EnvironmentObject var vm: StudyViewModel
    @State private var name = ""; @State private var surname = ""; @State private var dept = "Sınıf Öğretmenliği"; @State private var date = Date(); @State private var avatar = "👩‍🎓"; @State private var item: PhotosPickerItem?; @State private var data: Data?
    var body: some View {
        ZStack {
            LinearGradient(colors: [.purple, .indigo], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 30) {
                    Spacer(minLength: 50); Text("KPSS ASİSTANIM").font(.system(size: 40, weight: .heavy)).foregroundColor(.white); Text("Bilgilerini gir, hedefine ulaş.").foregroundColor(.white.opacity(0.8))
                    VStack { if let d=data, let ui=UIImage(data: d){ Image(uiImage: ui).resizable().scaledToFill().frame(width:100, height:100).clipShape(Circle()).overlay(Circle().stroke(.white, lineWidth:3)) } else { Text(avatar).font(.system(size: 80)).padding().background(Circle().fill(.white.opacity(0.2))) }; ScrollView(.horizontal){ HStack{ ForEach(vm.cuteAvatars, id:\.self){ a in Button(a){avatar=a;data=nil}.font(.largeTitle).padding(10).background(avatar==a ? Color.white.opacity(0.3):Color.clear).clipShape(Circle()) }; PhotosPicker(selection:$item, matching:.images){ Image(systemName:"photo.badge.plus").font(.title).foregroundColor(.white) }
                        .onChange(of: item) { _, newItem in
                            Task { if let d = try? await newItem?.loadTransferable(type: Data.self) { data = d; avatar = "custom" } }
                        }
                    } }.padding() }
                    VStack(spacing:15){ TextField("Ad", text:$name).padding().background(Color.white).cornerRadius(10); TextField("Soyad", text:$surname).padding().background(Color.white).cornerRadius(10); HStack{ Text("Bölüm").foregroundColor(.white); Spacer(); Picker("", selection:$dept){ ForEach(vm.departments, id:\.self){ Text($0).tag($0) } }.accentColor(.white) }.padding().background(Color.white.opacity(0.2)).cornerRadius(10); DatePicker("Sınav Tarihi", selection:$date, displayedComponents:.date).colorScheme(.dark).padding().background(Color.white.opacity(0.2)).cornerRadius(10) }.padding()
                    Button("BAŞLA 🚀"){ vm.updateUser(name:name, surname:surname, department:dept, date:date, avatar:avatar, imageData:data) }.font(.headline).foregroundColor(.purple).frame(maxWidth:.infinity).padding().background(Color.white).cornerRadius(15).padding(.horizontal).disabled(name.isEmpty)
                    Spacer()
                }
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var viewModel: StudyViewModel
    init() { let a = UITabBarAppearance(); a.configureWithOpaqueBackground(); a.backgroundColor = UIColor.systemGray6; UITabBar.appearance().standardAppearance = a; UITabBar.appearance().scrollEdgeAppearance = a }
    var body: some View {
        TabView {
            MainContainer(title: "Ders Programı") { AllSubjectsView() }.tabItem { Label("Dersler", systemImage: "books.vertical.fill") }
            MainContainer(title: "Doğru/Yanlış") { FlashcardView() }.tabItem { Label("Kartlar", systemImage: "rectangle.portrait.on.rectangle.portrait.angled.fill") }
            MainContainer(title: "Video Kampı") { VideoTrackerView() }.tabItem { Label("Videolar", systemImage: "play.rectangle.fill") }
            ProfileView().tabItem { Label("Analiz & Profil", systemImage: "chart.bar.xaxis") }
        }.tint(.purple)
    }
}

struct MainContainer<Content: View>: View {
    @EnvironmentObject var vm: StudyViewModel; let title: String; let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View { NavigationStack { VStack(spacing: 0) { if let d = vm.userProfile?.examDate { DetailedCountdownBar(targetDate: d) }; content }.navigationTitle(title).navigationBarTitleDisplayMode(.inline) } }
}

// MARK: - 6. VİDEO EKRANI

struct VideoTrackerView: View {
    @EnvironmentObject var vm: StudyViewModel; @State private var show = false; @State private var del: String?
    var grp: [String:[VideoLesson]] { Dictionary(grouping: vm.videos, by: {$0.subject}) }
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            if vm.videos.isEmpty && !vm.isFetchingVideos {
                VStack(spacing: 15) {
                    Image(systemName: "video.badge.plus").font(.system(size: 60)).foregroundColor(.gray)
                    Text("Henüz video eklemedin.").font(.headline).foregroundColor(.gray)
                    Text("Playlist linki yapıştırarak tüm videoları çekebilirsin.").font(.caption).foregroundColor(.secondary)
                    if let err = vm.fetchError { Text(err).foregroundColor(.red).bold() }
                }
            } else {
                List {
                    ForEach(grp.keys.sorted(), id: \.self) { k in
                        Section(header: HStack { Text(k).font(.headline).foregroundColor(.purple); Spacer(); Button{del=k}label:{Image(systemName:"trash").foregroundColor(.red)}.buttonStyle(BorderlessButtonStyle()) }) {
                            ForEach(grp[k]!) { v in
                                HStack(alignment: .top) {
                                    Link(destination: URL(string:"https://www.youtube.com/watch?v=\(v.youtubeId)")!) {
                                        ZStack {
                                            AsyncImage(url: URL(string: v.thumbnailUrl)){i in i.resizable().scaledToFill()}placeholder:{Color.gray.opacity(0.3)}.frame(width:90, height:60).cornerRadius(8).clipped()
                                            Image(systemName:"play.fill").foregroundColor(.white)
                                        }
                                    }.buttonStyle(PlainButtonStyle())
                                    VStack(alignment:.leading) {
                                        Text(v.title).font(.subheadline).fixedSize(horizontal:false, vertical:true).lineLimit(nil)
                                        HStack { Image(systemName:"youtube").foregroundColor(.red); Text("YouTube").font(.caption2).foregroundColor(.secondary) }
                                    }.layoutPriority(1)
                                    Spacer()
                                    Button{vm.toggleVideo(v)}label:{Image(systemName: v.isWatched ? "checkmark.circle.fill" : "circle").font(.title2).foregroundColor(v.isWatched ? .green : .gray)}.buttonStyle(PlainButtonStyle())
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }.listStyle(.insetGrouped)
            }
        }
        .toolbar { Button{show=true}label:{Image(systemName:"plus.circle.fill").foregroundColor(.purple)} }
        .sheet(isPresented: $show) { AddPlaylistSheet() }
        .confirmationDialog("Sil", isPresented: Binding(get:{del != nil}, set:{if !$0{del=nil}})){ Button("Sil", role:.destructive){if let n=del{vm.removePlaylist(subjectName: n)}} }
        .overlay { if vm.isFetchingVideos { ZStack{ Color.black.opacity(0.4).ignoresSafeArea(); VStack{ ProgressView().tint(.white); Text("Videolar Çekiliyor...").foregroundColor(.white).bold() }.padding(30).background(Color.gray.opacity(0.9)).cornerRadius(15) } } }
    }
}

struct AddPlaylistSheet: View {
    @EnvironmentObject var vm: StudyViewModel; @Environment(\.dismiss) var dismiss; @State private var s=""; @State private var l=""
    var body: some View { NavigationStack { Form { Section("Bilgi") { TextField("Ders Adı", text: $s); TextField("Link", text: $l) }; Button("Getir") { dismiss(); vm.fetchRealYouTubePlaylist(subjectName: s, playlistLink: l) } } } }
}

// MARK: - 7. DİĞER

struct ProfileView: View {
    @EnvironmentObject var vm: StudyViewModel; @State private var showEdit = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 25) {
                    if let user = vm.userProfile {
                        HStack {
                            if let data = user.customImageData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage).resizable().scaledToFill().frame(width: 80, height: 80).clipShape(Circle()).overlay(Circle().stroke(.purple, lineWidth: 3))
                            } else {
                                Text(user.avatarSelection).font(.system(size: 60)).padding(10).background(Circle().fill(.purple.opacity(0.1)))
                            }
                            VStack(alignment: .leading) { Text("\(user.name) \(user.surname)").font(.title2).bold(); Text(user.department).font(.subheadline).foregroundColor(.secondary) }
                            Spacer()
                            Button("Düzenle") { showEdit = true }.font(.caption).padding(8).background(Color.gray.opacity(0.1)).cornerRadius(20)
                        }.padding().background(Color.white).cornerRadius(20).padding(.horizontal).shadow(radius: 2)
                        
                        HStack(spacing: 30) {
                            ProgressRing(progress: vm.totalProgress, color: .blue, title: "Konular", icon: "book.fill")
                            ProgressRing(progress: vm.videoProgress, color: .red, title: "Videolar", icon: "play.fill")
                        }.padding().background(Color.white).cornerRadius(20).shadow(radius: 2).padding(.horizontal)
                        
                        VStack(alignment: .leading) {
                            Text("Ders Konu Analizi").font(.headline).padding(.bottom, 5)
                            let stats = vm.getSubjectStats()
                            if stats.isEmpty { Text("Veri Yok").font(.caption).foregroundColor(.secondary) }
                            else {
                                Chart {
                                    ForEach(stats) { stat in
                                        BarMark(x: .value("Ders", stat.category), y: .value("Sayı", stat.count))
                                            .foregroundStyle(by: .value("Durum", stat.type))
                                            .position(by: .value("Durum", stat.type))
                                    }
                                }.chartForegroundStyleScale(["Toplam": Color.gray.opacity(0.3), "Tamamlanan": Color.blue]).frame(height: 200)
                            }
                        }.padding().background(Color.white).cornerRadius(20).shadow(radius: 2).padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Video Kampı Durumu").font(.headline)
                            let grouped = Dictionary(grouping: vm.videos, by: { $0.subject })
                            if grouped.isEmpty { Text("Video eklenmedi.").font(.caption).foregroundColor(.secondary) }
                            else {
                                ForEach(grouped.keys.sorted(), id: \.self) { subject in
                                    let videos = grouped[subject]!; let total = videos.count; let watched = videos.filter{$0.isWatched}.count; let ratio = Double(watched)/Double(total)
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack { Text(subject).font(.subheadline).bold(); Spacer(); Text("\(watched)/\(total)").font(.caption).foregroundColor(.secondary) }
                                        GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(Color.gray.opacity(0.2)).frame(height: 8); Capsule().fill(Color.red).frame(width: g.size.width * ratio, height: 8) } }.frame(height: 8)
                                    }
                                }
                            }
                        }.padding().background(Color.white).cornerRadius(20).shadow(radius: 2).padding(.horizontal)
                    }
                }.padding(.top)
            }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Analiz & Profil").sheet(isPresented: $showEdit) { EditProfileView() }
        }
    }
}

struct ProgressRing: View { let progress: Double; let color: Color; let title: String; let icon: String
    var body: some View { VStack { ZStack { Circle().stroke(color.opacity(0.2), lineWidth: 10); Circle().trim(from: 0, to: progress).stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90)).animation(.easeOut, value: progress); VStack { Image(systemName: icon).font(.title2).foregroundColor(color); Text("%\(Int(progress * 100))").font(.headline).bold() } }.frame(width: 80, height: 80); Text(title).font(.caption).bold().foregroundColor(.secondary) }.frame(maxWidth: .infinity) } }

struct AllSubjectsView: View { @State private var tab="Tümü"; let cats=["Türkçe","Matematik","Tarih","Coğrafya","Vatandaşlık"]; var body: some View { VStack { ScrollView(.horizontal, showsIndicators:false) { HStack { ForEach(cats, id:\.self) { c in Button(action:{tab=c}) { Text(c).padding(.horizontal,15).padding(.vertical,8).background(tab==c ? Color.purple : Color.gray.opacity(0.2)).foregroundColor(tab==c ? .white : .black).cornerRadius(20) } } }.padding() }; SubjectPageViewContent(category:tab, color:tab=="Türkçe" ? .pink:.blue) } } }

struct SubjectPageViewContent: View { @EnvironmentObject var vm: StudyViewModel; let category: String; let color: Color; @State private var show = false
    var filtered: [Subject] { vm.subjects.filter { $0.category == category || category == "Tümü" } }
    var body: some View { List { if category != "Tümü" { Section { ProgressView(value: vm.progress(for: category)).tint(color) } }; Section("Konular") { ForEach(filtered) { s in HStack { Image(systemName: s.isCompleted ? "checkmark.circle.fill" : "circle").foregroundColor(s.isCompleted ? .green : .gray).onTapGesture { vm.toggleSubject(s) }; VStack(alignment:.leading){ Text(s.name); Text(s.category).font(.caption).foregroundColor(.secondary) }; Spacer(); if s.scheduledDate != nil { Text("📅").font(.caption) } }.swipeActions { Button("Sil", role: .destructive) { vm.deleteSubject(s) } } } } }.toolbar { Button{show=true}label:{Image(systemName:"plus")} }.sheet(isPresented: $show) { AddSubjectSheet(category: category == "Tümü" ? "Türkçe" : category) } } }

struct AddSubjectSheet: View {
    @EnvironmentObject var vm: StudyViewModel
    @Environment(\.dismiss) var dismiss
    let category: String
    
    @State private var n = ""
    @State private var note = ""
    @State private var d = Date()
    @State private var notif = false
    @State private var selectedCat = "Türkçe" // Varsayılan
    
    var body: some View {
        Form {
            Picker("Ders", selection: $selectedCat) {
                ForEach(["Türkçe","Matematik","Tarih", "Coğrafya", "Vatandaşlık"], id:\.self) { Text($0).tag($0) }
            }
            TextField("Konu", text: $n)
            TextField("Not", text: $note)
            DatePicker("Tarih", selection: $d).environment(\.locale, Locale(identifier: "tr_TR"))
            Toggle("Bildirim", isOn: $notif)
            Button("Ekle") {
                vm.addSubject(name: n, category: selectedCat, note: note, date: d, hasNotification: notif)
                dismiss()
            }.disabled(n.isEmpty)
        }
        .onAppear {
            if category != "Tümü" {
                selectedCat = category
            }
        }
    }
}

struct FlashcardView: View { @EnvironmentObject var vm: StudyViewModel; var body: some View { ZStack { Color(uiColor: .systemGroupedBackground).ignoresSafeArea(); if vm.isSessionFinished { ScrollView { VStack(spacing: 20) { Text("Sonuçlar").font(.largeTitle).bold().padding(.top); HStack { VStack { Text("\(vm.sessionResult.correctCount)").font(.largeTitle).bold().foregroundColor(.green); Text("Doğru") }; Spacer().frame(width: 40); VStack { Text("\(vm.sessionResult.incorrectCount)").font(.largeTitle).bold().foregroundColor(.red); Text("Yanlış") } }.padding().background(Color.white).cornerRadius(15); if !vm.sessionResult.wrongCards.isEmpty { ForEach(vm.sessionResult.wrongCards) { c in VStack(alignment: .leading) { HStack { Image(systemName: "xmark.circle.fill").foregroundColor(.red); Text(c.statement).bold() }; Divider(); Text("Doğrusu: \(c.explanation)").font(.subheadline).foregroundColor(.secondary) }.padding().background(Color.white).cornerRadius(10).padding(.horizontal) } } else { Text("Tebrikler!").padding() }; Button("Tekrar") { _ = withAnimation { vm.resetSession() } }.padding().background(Color.purple).foregroundColor(.white).cornerRadius(10) } } } else { ZStack { ForEach(vm.activeFlashcards.reversed()) { c in TrueFalseCard(card: c) { r in vm.processCardSwipe(card: c, userSwipedRight: r) } } }.padding() } } } }

struct ScoreCard: View { let title: String; let count: Int; let color: Color
    var body: some View { VStack { Text("\(count)").font(.system(size: 40, weight: .bold)).foregroundColor(color); Text(title).font(.headline).foregroundColor(.secondary) }.frame(maxWidth: .infinity).padding().background(Color.white).cornerRadius(15).shadow(radius: 2) } }

struct TrueFalseCard: View { let card: Flashcard; var onSwipe: (Bool) -> Void; @State private var off = CGSize.zero; @State private var col: Color = .white
    var body: some View { ZStack { RoundedRectangle(cornerRadius: 20).fill(col).shadow(radius: 5); VStack(spacing: 15) { Text(card.category).font(.caption).padding(5).background(Color.purple.opacity(0.1)).cornerRadius(5); Text(card.statement).font(.title2).bold().multilineTextAlignment(.center).padding(); Text("(Sağ: Doğru, Sol: Yanlış)").font(.caption).foregroundColor(.gray) }.padding() }.frame(width: 320, height: 400).rotationEffect(.degrees(Double(off.width/20))).offset(x: off.width).gesture(DragGesture().onChanged{ g in off = g.translation; col = off.width > 0 ? .green.opacity(0.2) : .red.opacity(0.2) }.onEnded{ _ in if abs(off.width) > 100 { onSwipe(off.width > 0) } else { _ = withAnimation { off = .zero; col = .white } } }) } }

struct EditProfileView: View { @EnvironmentObject var vm: StudyViewModel; @Environment(\.dismiss) var dismiss; @State private var name=""; @State private var surname=""; @State private var dept=""; @State private var date=Date(); @State private var avatar=""; @State private var item: PhotosPickerItem?; @State private var data: Data?
    var body: some View { Form { TextField("Ad", text:$name); TextField("Soyad", text:$surname); DatePicker("Tarih", selection:$date).environment(\.locale, Locale(identifier: "tr_TR")); Button("Kaydet"){vm.updateUser(name:name, surname:surname, department:dept, date:date, avatar:avatar, imageData:data); dismiss()} }.onAppear{if let u=vm.userProfile{name=u.name;surname=u.surname;date=u.examDate;avatar=u.avatarSelection;data=u.customImageData}} } }

struct DetailedCountdownBar: View { let targetDate: Date; @State private var s = "..."; let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View { HStack { Image(systemName: "timer").foregroundColor(.white); Text(s).font(.system(.body, design: .monospaced)).bold().foregroundColor(.white) }.frame(maxWidth: .infinity).padding(.vertical, 8).background(Color.purple).onReceive(timer) { _ in update() }.onAppear{ update() } }
    func update() { let diff = Calendar.current.dateComponents([.day, .hour, .minute, .second], from: Date(), to: targetDate); if let d = diff.day, let h = diff.hour, let m = diff.minute, let sec = diff.second { s = String(format: "%02d GÜN %02d:%02d:%02d", max(0, d), max(0, h), max(0, m), max(0, sec)) } } }
