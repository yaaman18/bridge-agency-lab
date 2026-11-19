#include "ofApp.h"
#include "instrument_tables.h"
#include "bell_tables.h"
static_assert(Bell::P == bell::P, "Bell::P must match bell_tables.h");
#include <chrono>
#include "imgui_internal.h"
#ifdef IMGUI_ENABLE_FREETYPE
#include "imgui_freetype.h"
#endif
#include <fstream>
#include <sstream>

static double wallNow() {
    using namespace std::chrono;
    return duration_cast<microseconds>(system_clock::now().time_since_epoch()).count() / 1e6;
}

static std::vector<std::string> splitTab(const std::string &s) {
    std::vector<std::string> out;
    std::string cur;
    for (char ch : s) {
        if (ch == '\t') { out.push_back(cur); cur.clear(); }
        else if (ch != '\r') cur.push_back(ch);
    }
    out.push_back(cur);
    return out;
}

static long toLong(const std::string &s) {
    if (s.empty() || s == "-") return -1;
    char *e = nullptr;
    long v = std::strtol(s.c_str(), &e, 10);
    return (e && *e == 0) ? v : -1;
}

void ofApp::setup() {
    const char *home = std::getenv("HOME");
    lab = std::string(home ? home : "") + "/bridge-agency-lab";
    // Retina: oF counts in framebuffer pixels; keep the window 1280x720 points (the picture and the text at full density)
    if (auto *gw = dynamic_cast<ofAppGLFWWindow *>(ofGetWindowPtr())) {
        int k = gw->getPixelScreenCoordScale();
        if (k > 1) ofSetWindowShape(1280 * k, 720 * k);
    }
    ofSetFrameRate(60);
    ofSetVerticalSync(true);
    ofBackground(0);
    shader.load("shaders/scene");
    setupGui();
    view.setup(lab + "/viewer/s54-of/data");
    loadRefs();
    reloadTsv();

    reverb.setup(48000);
    for (int c = 0; c < 2; ++c) itdBuf[c].assign(64, 0.0f);
    ofSoundStreamSettings s;
    s.setOutListener(this);
    s.sampleRate = 48000;
    s.numOutputChannels = 2;
    s.numInputChannels = 0;
    s.bufferSize = 512;
    stream.setup(s);
    sr = 48000;
    if (const char *m = std::getenv("S54_MUTE")) muteUi = std::string(m) == "1";
    if (const char *rv = std::getenv("S54_REVERB")) reverbUi = std::string(rv) != "0";
    if (const char *bi = std::getenv("S54_BINAURAL")) binauralUi = std::string(bi) == "1";
    if (const char *so = std::getenv("S54_SOLO")) {
        if (std::string(so) == "piano") soloBell = 0;
        if (std::string(so) == "bell") soloPiano = 0;
    }
    if (std::getenv("S54_WAV")) { rec.reserve(48000 * 2 * 30); recording = true; }
    if (const char *wv = std::getenv("S54_DEMO_WARP")) demoWarp = std::max(1.0, std::atof(wv));
    if (const char *lk = std::getenv("S54_LOOK")) view.look.mode = ofClamp(std::atoi(lk), 0, 4); // for test shots
    if (const char *d = std::getenv("S54_DEMO")) if (std::string(d) == "1") keyPressed('d');
}

void ofApp::loadRefs() {
    const char *names[2] = {"ref-669-L2.sha", "ref-669-L2SF.sha"};
    for (int c = 0; c < 2; ++c) {
        std::ifstream f(lab + "/experiments/trial-data/" + names[c]);
        std::string line;
        while (std::getline(f, line)) {
            std::istringstream is(line);
            long n; std::string hex;
            if (!(is >> n >> hex) || hex.size() < 64 || n < 0) continue;
            if ((long)ref[c].size() <= n) ref[c].resize(n + 1);
            for (int b = 0; b < 32; ++b) ref[c][n][b] = (uint8_t)std::stoi(hex.substr(2 * b, 2), nullptr, 16);
        }
        ofLogNotice() << names[c] << ": " << ref[c].size() << " steps";
    }
    std::ifstream f(lab + "/experiments/trial-data/drives-669.txt");
    int a, b;
    while (f >> a >> b) drives.push_back({a, b});
    ofLogNotice() << "drives: " << drives.size();
}

void ofApp::reloadTsv() {
    std::ifstream f(lab + "/experiments/s54-watch.tsv");
    if (!f) return;
    std::vector<WatchRow> rs;
    std::string line;
    while (std::getline(f, line)) {
        if (line.empty() || line[0] == '#' || line.rfind("mac_time", 0) == 0) continue;
        auto v = splitTab(line);
        if (v.size() < 17) continue;
        WatchRow r;
        r.time = v[0]; r.epoch = toLong(v[1]); r.boot = v[2]; r.thr = v[3];
        r.ext4 = v[4]; r.fsState = v[5]; r.fsErr = v[6];
        for (int c = 0; c < 2; ++c) {
            r.life[c].unit = v[7 + 5 * c];
            r.life[c].n = toLong(v[8 + 5 * c]);
            r.life[c].match = v[10 + 5 * c];
        }
        rs.push_back(r);
    }
    int changes = 0;
    std::string first, prev;
    for (auto &r : rs) {
        if (r.boot == "unreachable" || r.boot == "ERR") continue;
        if (first.empty()) first = r.boot;
        if (!prev.empty() && r.boot != prev) ++changes;
        prev = r.boot;
    }
    if (!rows.empty() && changes > bootChanges) flash = 1.0f;
    bootChanges = changes;
    firstBoot = first;
    rows.swap(rs);
}

double ofApp::simNow() const {
    double r = wallNow();
    return demo ? demoAnchorSim + (r - demoAnchorReal) * demoWarp : r;
}

void ofApp::update() {
    float t = ofGetElapsedTimef();
    if (t - lastReload > 20) { reloadTsv(); lastReload = t; }
    flash *= 0.97f;
    if (rows.empty()) { view.update(stepF); return; }
    const WatchRow &last = rows.back();
    double now = simNow();
    for (int c = 0; c < 2; ++c) {
        // last row with a readable n for this life
        long nObs = -1, ep = 0;
        for (auto it = rows.rbegin(); it != rows.rend(); ++it)
            if (it->life[c].n >= 0) { nObs = it->life[c].n; ep = it->epoch; break; }
        const std::string &u = last.life[c].unit;
        obsDead[c] = !(u == "active" || u == "unreachable" || u == "?" || u == "activating");
        mismatch[c] = last.life[c].match == "false";
        if (nObs < 0) { stepF[c] = 0; continue; }
        double est = nObs + std::max(0.0, now - ep) / 10.0;
        expDead[c] = est >= deadAt[c];
        if (obsDead[c]) stepF[c] = nObs;
        else stepF[c] = std::min(est, (double)deadAt[c]);
        float target = (obsDead[c] || expDead[c]) ? 0.0f : 1.0f;
        alive[c] += (target - alive[c]) * 0.01f;
    }
    stale = !demo && (wallNow() - last.epoch > 75 * 60);
    heat = !(last.thr == "0x0" || last.thr == "?" || last.thr == "ERR");
    fsBad = (last.ext4 != "0" && last.ext4 != "ERR") || (last.fsState != "clean" && last.fsState != "ERR") ||
            (last.fsErr != "0" && last.fsErr != "ERR");
    unreachable = last.boot == "unreachable";

    view.update(stepF);
    std::lock_guard<std::mutex> lk(mtx);
    for (int c = 0; c < 2; ++c) {
        params.stepF[c] = stepF[c];
        params.alive[c] = alive[c];
        params.mismatch[c] = mismatch[c];
    }
    params.rate = demo ? demoWarp / 10.0 : 0.1;
    params.stale = stale || unreachable;
    params.heat = heat;
    params.fsBad = fsBad;
    params.volume = volumeUi;
    params.mute = muteUi;
    params.reverb = reverbUi;
    params.binaural = binauralUi;
}

void ofApp::draw() {
    float w = ofGetWidth(), h = ofGetHeight();
    float prog[2], hue[2], y[2], pul[2], mis[2], al[2];
    for (int c = 0; c < 2; ++c) {
        long n = (long)stepF[c];
        prog[c] = (float)std::min(1.0, stepF[c] / deadAt[c]);
        float target = (n >= 0 && n < (long)ref[c].size()) ? ref[c][n][0] / 255.0f : 0.5f;
        float dh = target - hueS[c];
        dh -= std::round(dh);              // shortest way around the hue circle
        hueS[c] = hueS[c] + dh * 0.01f;
        hueS[c] -= std::floor(hueS[c]);
        hue[c] = hueS[c];
        y[c] = (n >= 0 && n < (long)drives.size()) ? drives[n][c] / 5.0f : 0.0f;
        pul[c] = pulse[c];
        mis[c] = mismatch[c] ? 1.0f : 0.0f;
        al[c] = alive[c];
    }
    // the picture goes into an fbo at renderScale of the window's pixels; the text (ImGui) is drawn at full resolution
    float rs = view.look.renderScale;
    int fw = std::max(16, (int)std::lround(w * rs)), fh = std::max(16, (int)std::lround(h * rs));
    if (!fbo.isAllocated() || fbo.getWidth() != fw || fbo.getHeight() != fh) {
        ofFboSettings fs;
        fs.width = fw; fs.height = fh;
        fs.internalformat = GL_RGBA;
        fs.useDepth = true;
        fs.numSamples = 4;
        fbo.allocate(fs);
    }
    fbo.begin();
    if (view.look.mode == 0) {
        shader.begin();
        shader.setUniform1f("uTime", ofGetElapsedTimef());
        shader.setUniform2f("uRes", fw * (1 - view.reserveFrac), fh);
        shader.setUniform1fv("uAlive", al, 2);
        shader.setUniform1fv("uProg", prog, 2);
        shader.setUniform1fv("uHue", hue, 2);
        shader.setUniform1fv("uYield", y, 2);
        shader.setUniform1fv("uPulse", pul, 2);
        shader.setUniform1fv("uMis", mis, 2);
        shader.setUniform1f("uStale", (stale || unreachable) ? 1.0f : 0.0f);
        shader.setUniform1f("uHeat", heat ? 1.0f : 0.0f);
        shader.setUniform1f("uFsBad", fsBad ? 1.0f : 0.0f);
        shader.setUniform1f("uFlash", flash);
        ofClear(0, 0, 0, 255);
        ofDrawRectangle(0, 0, fw * (1 - view.reserveFrac), fh);
        shader.end();
    } else {
        view.drawScene(fw, fh, 1, al, hue, mismatch, stale || unreachable);
    }
    fbo.end();
    ofSetColor(255);
    fbo.draw(0, 0, w, h);

    gui.begin();
    ImVec2 ds = ImGui::GetIO().DisplaySize;
    view.reserveFrac = panelOpen ? 358.0f / ds.x : 0.0f; // applies from the next frame's picture
    if (view.look.mode != 0) view.drawOverlay(ds.x, ds.y, hue);
    if (panelOpen) view.panel(&panelOpen);
    if (hud) drawHud(hue);
    gui.end();
    gui.draw();
    if (const char *shot = std::getenv("S54_SHOT")) {
        if (ofGetFrameNum() == (std::getenv("S54_WAV") ? 1500 : 300)) {
            ofLogNotice() << "frame rate at the shot: " << ofGetFrameRate();
            ofSaveScreen(shot);
            if (recording) {
                stream.close();
                writeWav(std::getenv("S54_WAV"));
            }
            ofExit(0);
        }
    }
}

static ImVec4 hueColor(float h, float s = 0.55f, float v = 1.0f) {
    float r, g, b;
    ImGui::ColorConvertHSVtoRGB(h - std::floor(h), s, v, r, g, b);
    return ImVec4(r, g, b, 1);
}

void ofApp::setupGui() {
    gui.setup(nullptr, false, ImGuiConfigFlags_None, false, false);
    ImGuiIO &io = ImGui::GetIO();
    io.IniFilename = nullptr; // no imgui.ini: the panel's numbers are saved as looks (bin/data/looks)
    // fonts: vector outlines rasterised by FreeType at the display's density (Retina: 2x), so they stay sharp
    auto add = [&](std::initializer_list<const char *> paths, float size, bool merge) -> ImFont * {
        for (const char *p : paths) {
            if (!ofFile::doesFileExist(p, false)) continue;
            ImFontConfig cfg;
            cfg.MergeMode = merge;
#ifdef IMGUI_ENABLE_FREETYPE
            cfg.FontLoaderFlags = ImGuiFreeTypeLoaderFlags_LightHinting;
#endif
            return io.Fonts->AddFontFromFileTTF(p, size, &cfg);
        }
        return nullptr;
    };
    const char *jpW3 = "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc", *jpW6 = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc";
    fontMain = add({"/Library/Fonts/SF-Pro-Text-Regular.otf", "/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"}, 15, false);
    if (fontMain) add({jpW3}, 15, true);
    fontTitle = add({"/Library/Fonts/SF-Pro-Text-Semibold.otf", "/System/Library/Fonts/SFNS.ttf"}, 16, false);
    if (fontTitle) add({jpW6}, 16, true);
    fontMono = add({"/System/Library/Fonts/SFNSMono.ttf", "/System/Library/Fonts/Menlo.ttc"}, 13.5f, false);
    if (fontMono) add({jpW3}, 13.5f, true);
    if (fontMain) io.FontDefault = fontMain;
    if (!fontTitle) fontTitle = fontMain;
    if (!fontMono) fontMono = fontMain;

    // style: dark glass, rounded, one cool accent
    ImGuiStyle &st = ImGui::GetStyle();
    st.WindowRounding = 12; st.ChildRounding = 8; st.FrameRounding = 7; st.PopupRounding = 8;
    st.GrabRounding = 7; st.ScrollbarRounding = 8; st.TabRounding = 7;
    st.WindowPadding = ImVec2(16, 14); st.FramePadding = ImVec2(10, 6); st.ItemSpacing = ImVec2(10, 8);
    st.ItemInnerSpacing = ImVec2(8, 6); st.CellPadding = ImVec2(10, 4); st.GrabMinSize = 12;
    st.WindowBorderSize = 1; st.FrameBorderSize = 0; st.PopupBorderSize = 1;
    st.WindowTitleAlign = ImVec2(0.0f, 0.5f); st.SeparatorTextBorderSize = 1;
    ImVec4 acc(0.42f, 0.86f, 0.80f, 1), *c = st.Colors;
    auto A = [](ImVec4 v, float a) { v.w = a; return v; };
    c[ImGuiCol_Text] = ImVec4(0.92f, 0.93f, 0.95f, 1);
    c[ImGuiCol_TextDisabled] = ImVec4(0.56f, 0.59f, 0.66f, 1);
    c[ImGuiCol_WindowBg] = ImVec4(0.065f, 0.072f, 0.098f, 0.86f);
    c[ImGuiCol_PopupBg] = ImVec4(0.08f, 0.09f, 0.12f, 0.97f);
    c[ImGuiCol_Border] = ImVec4(1, 1, 1, 0.08f);
    c[ImGuiCol_FrameBg] = ImVec4(1, 1, 1, 0.055f);
    c[ImGuiCol_FrameBgHovered] = ImVec4(1, 1, 1, 0.09f);
    c[ImGuiCol_FrameBgActive] = ImVec4(1, 1, 1, 0.13f);
    c[ImGuiCol_TitleBg] = ImVec4(0.065f, 0.072f, 0.098f, 0.92f);
    c[ImGuiCol_TitleBgActive] = ImVec4(0.08f, 0.09f, 0.12f, 0.95f);
    c[ImGuiCol_TitleBgCollapsed] = A(c[ImGuiCol_TitleBg], 0.7f);
    c[ImGuiCol_CheckMark] = acc;
    c[ImGuiCol_SliderGrab] = A(acc, 0.85f);
    c[ImGuiCol_SliderGrabActive] = acc;
    c[ImGuiCol_Button] = ImVec4(1, 1, 1, 0.07f);
    c[ImGuiCol_ButtonHovered] = A(acc, 0.30f);
    c[ImGuiCol_ButtonActive] = A(acc, 0.45f);
    c[ImGuiCol_Header] = A(acc, 0.12f);
    c[ImGuiCol_HeaderHovered] = A(acc, 0.22f);
    c[ImGuiCol_HeaderActive] = A(acc, 0.32f);
    c[ImGuiCol_Separator] = ImVec4(1, 1, 1, 0.08f);
    c[ImGuiCol_SeparatorHovered] = A(acc, 0.5f);
    c[ImGuiCol_ResizeGrip] = ImVec4(1, 1, 1, 0.05f);
    c[ImGuiCol_ResizeGripHovered] = A(acc, 0.4f);
    c[ImGuiCol_ScrollbarBg] = ImVec4(0, 0, 0, 0);
    c[ImGuiCol_ScrollbarGrab] = ImVec4(1, 1, 1, 0.10f);
    c[ImGuiCol_TableHeaderBg] = ImVec4(1, 1, 1, 0.04f);
    c[ImGuiCol_TableBorderLight] = ImVec4(1, 1, 1, 0.06f);
    c[ImGuiCol_TableBorderStrong] = ImVec4(1, 1, 1, 0.10f);
    c[ImGuiCol_TextSelectedBg] = A(acc, 0.30f);
}

void ofApp::drawHud(float hue[2]) {
    ImVec2 ds = ImGui::GetIO().DisplaySize;
    const ImGuiWindowFlags fl = ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoMove |
                                ImGuiWindowFlags_NoFocusOnAppearing | ImGuiWindowFlags_NoNav | ImGuiWindowFlags_NoSavedSettings;
    auto banner = [&](const char *id, float y, ImVec4 bg, const std::string &text) {
        ImGui::SetNextWindowPos(ImVec2(ds.x * 0.5f, y), ImGuiCond_Always, ImVec2(0.5f, 0));
        ImGui::PushStyleColor(ImGuiCol_WindowBg, bg);
        ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 20);
        ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(18, 7));
        ImGui::Begin(id, nullptr, fl);
        ImGui::PushFont(fontTitle, 0.0f);
        ImGui::TextUnformatted(text.c_str());
        ImGui::PopFont();
        ImGui::End();
        ImGui::PopStyleVar(2);
        ImGui::PopStyleColor();
    };
    float by = 14;
    if (demo) { banner("##demo", by, ImVec4(0.55f, 0.06f, 0.08f, 0.88f), "DEMO  模擬の時間（試運転ではない）"); by += 44; }
    if (view.scrub && view.look.mode != 0) banner("##scrub", by, ImVec4(0.50f, 0.36f, 0.05f, 0.88f), "絵は手で選んだ歩（音と HUD は推定の歩のまま）");

    long nObs[2] = {-1, -1};
    for (int c = 0; c < 2; ++c)
        for (auto it = rows.rbegin(); it != rows.rend(); ++it)
            if (it->life[c].n >= 0) { nObs[c] = it->life[c].n; break; }

    // the Pi and the watch: top left
    ImGui::SetNextWindowPos(ImVec2(14, 14), ImGuiCond_Always);
    ImGui::SetNextWindowBgAlpha(view.look.hudAlpha);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(12, 8));
    ImGui::Begin("##pi", nullptr, fl);
    ImGui::PushFont(fontMono, 12.0f);
    if (rows.empty()) {
        ImGui::Text("no watch rows yet (%s/experiments/s54-watch.tsv)", lab.c_str());
    } else {
        const WatchRow &r = rows.back();
        long age = (long)(wallNow() - r.epoch);
        ImGui::Text("last check %s  (%ld min ago)", r.time.c_str(), age / 60);
        if (stale) { ImGui::SameLine(); ImGui::TextColored(ImVec4(1, 0.6f, 0.3f, 1), "STALE"); }
        ImGui::TextDisabled("pi boot %s  changes %d  throttled %s  ext4 %s  fs %s/%s", r.boot.substr(0, 8).c_str(),
                            bootChanges, r.thr.c_str(), r.ext4.c_str(), r.fsState.c_str(), r.fsErr.c_str());
    }
    ImGui::PopFont();
    ImGui::PushFont(nullptr, 12.0f);
    if (view.look.mode != 0) ImGui::TextDisabled("絵の体の値は Mac で基準を計算し直したもの（6 歩ごと）。Pi から観測した値ではない。");
    ImGui::TextDisabled("n=60480 で入力が尽きる前に、Pi で n を確かめる（S54-start-procedure (f)）");
    ImGui::PopFont();
    ImGui::PushFont(fontMono, 11.0f);
    ImGui::TextDisabled("[g] panel [h] hud [f] full [1-5] look [m] mute%s [+/-] vol %.2f [d] demo x%d%s [v] reverb %s [b] binaural %s",
                        muteUi ? " ON" : "", volumeUi, (int)demoWarp, demo ? " ON" : "", reverbUi ? "on" : "off",
                        binauralUi ? "on" : "off");
    ImGui::PopFont();
    ImGui::End();
    ImGui::PopStyleVar();

    // one card under each life
    if (!rows.empty()) {
        const WatchRow &r = rows.back();
        for (int c = 0; c < 2; ++c) {
            float cx, top;
            if (view.look.mode == 0) {
                float aw = ds.x * (1 - view.reserveFrac);
                cx = aw * 0.5f + (c ? 1 : -1) * 0.27f * aw;
                top = ds.y * 0.76f;
            }
            else {
                ofRectangle br = view.bodyRect(c, ds.x, ds.y), cr = view.circuitRect(c, ds.x, ds.y);
                cx = br.getCenter().x;
                top = (view.look.mode == 3 ? cr.getBottom() : (view.look.circuit ? cr.getBottom() : br.getBottom())) + 10;
            }
            ImGui::SetNextWindowPos(ImVec2(cx, top), ImGuiCond_Always, ImVec2(0.5f, 0));
            ImGui::SetNextWindowBgAlpha(view.look.hudAlpha);
            ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(14, 10));
            ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(8, 3));
            ImGui::Begin(c ? "##card1" : "##card0", nullptr, fl);
            ImGui::PushFont(fontTitle, 15.0f);
            ImGui::TextColored(hueColor(hue[c] + (view.look.mode ? view.look.hueShift : 0)), "%s", c ? "試-2  L2+SF" : "試-1  L2");
            ImGui::PopFont();
            ImGui::SameLine();
            ImGui::PushFont(fontMono, 12.0f);
            ImGui::TextDisabled("unit %s", r.life[c].unit.c_str());
            ImGui::PopFont();
            if (ImGui::BeginTable("##t", 2, ImGuiTableFlags_SizingFixedFit)) {
                auto row = [&](const char *label, const std::string &v, bool mono = true) {
                    ImGui::TableNextRow();
                    ImGui::TableNextColumn();
                    ImGui::PushFont(nullptr, 12.5f);
                    ImGui::TextDisabled("%s", label);
                    ImGui::PopFont();
                    ImGui::TableNextColumn();
                    ImGui::PushFont(mono ? fontMono : nullptr, mono ? 12.5f : 13.0f);
                    ImGui::TextUnformatted(v.c_str());
                    ImGui::PopFont();
                };
                row("n 観測", ofToString(nObs[c]));
                row("n 推定", ofToString((long)stepF[c]));
                row("基準との一致", r.life[c].match);
                row("基準の死の歩", ofToString(deadAt[c]));
                if (obsDead[c]) row("状態", "止まった（観測）", false);
                else if (expDead[c]) row("状態", "基準の死に達した（確認待ち）", false);
                else row("状態", "基準の死まで 約 " + ofToString((deadAt[c] - stepF[c]) * 10.0 / 3600.0, 1) + " 時間", false);
                if (view.look.mode != 0) {
                    int i = view.shownFrame(c);
                    if (view.data[c].ok && i >= 0) {
                        const BodyFrame &F = view.data[c].frames[i];
                        int k = 0;
                        for (auto v : F.C) k += v != 0;
                        row("絵の体（基準）", "n " + ofToString(F.n) + "  C " + ofToString(k) + " 升");
                    }
                }
                ImGui::EndTable();
            }
            ImGui::End();
            ImGui::PopStyleVar(2);
        }
    }

}

void ofApp::keyPressed(int key) {
    if (ImGui::GetCurrentContext() && ImGui::GetIO().WantCaptureKeyboard) return;
    if (key == 'g') panelOpen = !panelOpen;
    else if (key >= '1' && key <= '5') view.look.mode = key - '1';
    else if (key == 'f') ofToggleFullscreen();
    else if (key == 'h') hud = !hud;
    else if (key == 'm') muteUi = !muteUi;
    else if (key == '+' || key == '=') volumeUi = std::min(1.0f, volumeUi + 0.05f);
    else if (key == '-') volumeUi = std::max(0.0f, volumeUi - 0.05f);
    else if (key == 'r') { reloadTsv(); }
    else if (key == 'v') reverbUi = !reverbUi;
    else if (key == 'b') binauralUi = !binauralUi;
    else if (key == 'd') {
        demo = !demo;
        demoAnchorReal = wallNow();
        demoAnchorSim = demoAnchorReal;
        for (int c = 0; c < 2; ++c) alive[c] = 1;
    }
}

// ---- tables from the MIS analysis (instrument_tables.h, tools/analyze.py)
static double lerp(double a, double b, double t) { return a + (b - a) * t; }

// bilinear lookup over dynamics (pp, mf, ff at d = 0, 0.5, 1) and register (A2..A5 at log2(f/110) = 0..3)
static double pianoLookup(const double tab[3][4], double d, double f) {
    double r = std::min(3.0, std::max(0.0, std::log2(f / 110.0)));
    int ri = std::min(2, (int)r); double rt = r - ri;
    double dd = std::min(1.0, std::max(0.0, d)) * 2; int di = std::min(1, (int)dd); double dt = dd - di;
    double a = lerp(tab[di][ri], tab[di][ri + 1], rt), b = lerp(tab[di + 1][ri], tab[di + 1][ri + 1], rt);
    return lerp(a, b, dt);
}
static double pianoLookupP(const double tab[3][4][inst::PP], int n, double d, double f) {
    double t2[3][4];
    for (int i = 0; i < 3; ++i) for (int j = 0; j < 4; ++j) t2[i][j] = tab[i][j][n];
    return pianoLookup(t2, d, f);
}
// bell decays: the fast stage is measured where a strike lifted the partial >= 6 dB (median of those otherwise);
// the slow stage is provisional (not measurable: the bells in the recording never stop): 9 s at the prime, shorter
// with height as (prime/f)^0.7. The slow share is what the strike did not lift: 10^(-jumpDb/20).
static double bellTau1(int n) {
    static double med = -1;
    if (med < 0) {
        std::vector<double> v;
        for (int k = 0; k < bell::P; ++k) if (bell::tau[k] > 0) v.push_back(bell::tau[k]);
        std::sort(v.begin(), v.end());
        med = v.empty() ? 0.3 : v[v.size() / 2];
    }
    return bell::tau[n] > 0 ? bell::tau[n] : med;
}

void ofApp::audioOut(ofSoundBuffer &buffer) {
    Params p;
    { std::lock_guard<std::mutex> lk(mtx); p = params; }
    static const double ratio[5] = {1.0, 9.0 / 8.0, 5.0 / 4.0, 3.0 / 2.0, 5.0 / 3.0};
    static const double base[2] = {220.0, 293.66};
    static const double mfPeak = inst::pianoPeak[1][2];
    static double samples = 0;
    static float crackle = 0;
    const size_t N = buffer.getNumFrames();
    const double slotLen = sr * 10.0 / 8.0; // eight piano notes per real 10 s
    for (size_t i = 0; i < N; ++i) {
        samples += 1;
        lfo += 2 * M_PI * 0.05 / sr;
        float outc[2] = {0, 0};
        for (int c = 0; c < 2; ++c) {
            double s = p.stepF[c] + p.rate * i / sr;
            long step = (long)s;
            bool have = step >= 0 && step < (long)ref[c].size();
            // ---- piano: the melody of the step's reference hash
            long slot = (long)((samples + c * slotLen * 0.5) / slotLen);
            if (slot != lastSlot[c]) {
                lastSlot[c] = slot;
                if (p.alive[c] > 0.05f && have) {
                    int k = (int)(slot % 8);
                    const auto &hb = ref[c][step];
                    uint8_t b0 = hb[4 * k], b1 = hb[4 * k + 1], b2 = hb[4 * k + 2], b3 = hb[4 * k + 3];
                    if (b3 >= 64) {
                        int vi = 0;
                        for (int v = 1; v < 6; ++v) if (voices[c][v].env < voices[c][vi].env) vi = v;
                        Voice &vo = voices[c][vi];
                        double f = base[c] * ratio[b0 % 5] * ((b1 % 3 == 0) ? 0.5 : (b1 % 3 == 1 ? 1.0 : 2.0));
                        double d = b2 / 255.0; // dynamics: 0 = pp, 0.5 = mf, 1 = ff
                        double B = pianoLookup(inst::pianoB, d, f);
                        double loud = 0.22 * pianoLookup(inst::pianoPeak, d, f) / mfPeak;
                        vo.env = 1; vo.dissonant = p.mismatch[c];
                        vo.hammer = 1; vo.hammerAmp = loud * std::pow(10.0, pianoLookup(inst::pianoHammerDb, d, f) / 20) * 40;
                        for (int n = 0; n < Voice::P; ++n) {
                            double m = n + 1, fn = f * m * std::sqrt(1 + B * m * m);
                            double a = (fn < sr * 0.45) ? loud * std::pow(10.0, pianoLookupP(inst::pianoAmpDb, n, d, f) / 20) : 0;
                            double t1 = std::min(3.0, std::max(0.05, pianoLookupP(inst::pianoTau1, n, d, f)));
                            double t2 = std::min(20.0, std::max(t1, pianoLookupP(inst::pianoTau2, n, d, f)));
                            double w2 = std::min(1.0, std::max(0.0, pianoLookupP(inst::pianoW2, n, d, f)));
                            vo.phase[n] = 0; vo.inc[n] = 2 * M_PI * fn / sr;
                            vo.a1[n] = a * (1 - w2); vo.a2[n] = a * w2;
                            vo.d1[n] = std::exp(-1.0 / (sr * t1)); vo.d2[n] = std::exp(-1.0 / (sr * t2));
                        }
                    }
                }
            }
            float x = 0, pk = 0;
            for (auto &vo : voices[c]) {
                if (vo.env < 1e-5) continue;
                double v = 0, e = 0;
                for (int n = 0; n < Voice::P; ++n) {
                    double a = vo.a1[n] + vo.a2[n];
                    if (a < 1e-7) continue;
                    vo.phase[n] += vo.inc[n];
                    v += a * std::sin(vo.phase[n]);
                    vo.a1[n] *= vo.d1[n]; vo.a2[n] *= vo.d2[n];
                    e += a;
                }
                if (vo.dissonant) v *= 0.7 + 0.3 * std::sin(vo.phase[0] * 0.0625);
                vo.hammer *= 0.996;
                v += vo.hammerAmp * vo.hammer * (frand() * 2 - 1);
                vo.env = e * 6;
                x += (float)v;
                pk = std::max(pk, (float)std::min(1.0, vo.env));
            }
            pulse[c] = pk;
            x *= soloPiano;
            // ---- bell: struck once per step, harder when the world's yield is high
            if (have && step != lastStep[c]) {
                lastStep[c] = step;
                if (p.alive[c] > 0.05f) {
                    uint8_t b = ref[c][step][31];
                    double f = base[c] * ratio[b % 5] * ((b >> 4) % 2 ? 2.0 : 1.0); // the prime
                    float yn = (step < (long)drives.size()) ? drives[step][c] / 5.0f : 0.0f;
                    double hit = 0.08 * (0.45 + 0.55 * yn);
                    Bell &bl = bells[c][bellNext[c]];
                    bellNext[c] ^= 1;
                    double pw = 0;
                    for (int n = 0; n < Bell::P; ++n) {
                        double fn = f * bell::ratio[n];
                        double a = (fn < sr * 0.45) ? hit * std::pow(10.0, bell::ampDb[n] / 20) : 0;
                        double w2 = std::pow(10.0, -bell::jumpDb[n] / 20);
                        double t1 = bellTau1(n), t2 = std::max(t1, 9.0 * std::pow(1.0 / bell::ratio[n], 0.7));
                        if (bell::ratio[n] < 1) t2 = 9.0 / std::pow(bell::ratio[n], 0.7); // the hum rings longest
                        // doublet split: 0.25-1.15 Hz, spread over the partials by the golden ratio (provisional)
                        double split = 0.25 + 0.9 * std::fmod((n + 1) * 0.6180339887, 1.0);
                        bl.phase[n] = 0; bl.inc[n] = 2 * M_PI * (fn - split / 2) / sr;
                        bl.phase2[n] = 0; bl.inc2[n] = 2 * M_PI * (fn + split / 2) / sr;
                        bl.a1[n] = a * (1 - w2); bl.a2[n] = a * w2;
                        bl.d1[n] = std::exp(-1.0 / (sr * t1)); bl.d2[n] = std::exp(-1.0 / (sr * t2));
                        pw += a * a / 2;
                    }
                    bl.clap = 1; bl.clapAmp = std::sqrt(pw * std::pow(10.0, bell::clapperDb / 10)) * 4;
                    bl.t = 0; bl.beat = p.mismatch[c]; bl.env = 1;
                }
            }
            double bs = 0;
            for (auto &bl : bells[c]) {
                if (bl.env < 1e-6) continue;
                double v = 0, e = 0;
                for (int n = 0; n < Bell::P; ++n) {
                    double a = bl.a1[n] + bl.a2[n];
                    if (a < 1e-8) continue;
                    bl.phase[n] += bl.inc[n]; bl.phase2[n] += bl.inc2[n];
                    v += a * (0.68 * std::sin(bl.phase[n]) + 0.32 * std::sin(bl.phase2[n])); // dips of about 9 dB
                    bl.a1[n] *= bl.d1[n]; bl.a2[n] *= bl.d2[n];
                    e += a;
                }
                bl.clap *= 0.995;
                float nz = frand() * 2 - 1;
                clapLp[c] += 0.5f * (nz - clapLp[c]);
                v += bl.clapAmp * bl.clap * (nz - clapLp[c]); // high-passed: the clapper's click
                bl.t += 1.0 / sr;
                if (bl.beat) v *= 0.6 + 0.4 * std::sin(2 * M_PI * 2.5 * bl.t); // out of step with the reference: it beats
                bl.env = e;
                bs += v;
            }
            x += (float)(bs * bellGain * soloBell);
            gainS[c] += ((0.15f + 0.85f * p.alive[c]) - gainS[c]) * 0.00002f;
            outc[c] = x * gainS[c];
        }
        // the Pi's health: throttling crackles, filesystem trouble hisses
        if (p.heat && frand() < 0.0006f) crackle = 0.4f;
        crackle *= 0.995f;
        float noise = (frand() * 2 - 1);
        float sys = crackle * noise + (p.fsBad ? 0.03f * noise : 0.0f);
        float o[2];
        if (p.binaural) {
            // near ear: direct; far ear: delayed by the ITD and shadowed
            static const int itd = (int)std::lround(0.0875 / 343.0 * (35 * M_PI / 180 + std::sin(35 * M_PI / 180)) * 48000);
            const float a = 1.0f - std::exp(-2 * (float)M_PI * 1200.0f / 48000.0f);
            float far[2];
            for (int c = 0; c < 2; ++c) {
                itdBuf[c][itdPos] = outc[c];
                float d = itdBuf[c][(itdPos + itdBuf[c].size() - itd) % itdBuf[c].size()];
                shadowLp[c] += a * (d - shadowLp[c]);
                far[c] = 0.9f * shadowLp[c] + 0.4f * (d - shadowLp[c]);
            }
            itdPos = (itdPos + 1) % itdBuf[0].size();
            for (int c = 0; c < 2; ++c) o[c] = 0.8f * (outc[c] + far[1 - c]) + sys; // 0.8: about the loudness of the plain mix
        } else {
            for (int c = 0; c < 2; ++c) o[c] = 0.8f * outc[c] + 0.2f * outc[1 - c] + sys;
        }
        // reverb: a large room, mixed under the dry sound
        if (p.reverb) {
            float w[2];
            reverb.process(0.015f * (o[0] + o[1]), w);
            for (int c = 0; c < 2; ++c) o[c] += 0.9f * w[c];
        }
        // stale data (or no answer from the Pi) muffles everything
        lpCut += ((p.stale ? 0.04f : 1.0f) - lpCut) * 0.00005f;
        for (int c = 0; c < 2; ++c) {
            lp[c] += lpCut * (o[c] - lp[c]);
            float v = p.mute ? 0.0f : p.volume * std::tanh(lp[c] * 1.2f);
            buffer[i * 2 + c] = v;
            if (recording && rec.size() < rec.capacity()) rec.push_back(v);
        }
    }
}

void ofApp::writeWav(const char *path) {
    std::ofstream f(path, std::ios::binary);
    auto w32 = [&](uint32_t v) { f.write((const char *)&v, 4); };
    auto w16 = [&](uint16_t v) { f.write((const char *)&v, 2); };
    uint32_t bytes = (uint32_t)rec.size() * 2;
    f.write("RIFF", 4); w32(36 + bytes); f.write("WAVEfmt ", 8); w32(16); w16(1); w16(2); w32(48000); w32(48000 * 4); w16(4); w16(16);
    f.write("data", 4); w32(bytes);
    for (float v : rec) { int16_t q = (int16_t)std::max(-32767.0f, std::min(32767.0f, v * 32767.0f)); f.write((const char *)&q, 2); }
}
