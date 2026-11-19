#include "BodyView.h"
#include <cstring>
#include <fstream>

// ---------------------------------------------------------------- data
static float half2float(uint16_t h) {
    uint32_t s = (h >> 15) & 1, e = (h >> 10) & 31, m = h & 1023;
    float v;
    if (e == 0) v = std::ldexp((float)m, -24);
    else if (e == 31) v = m ? NAN : INFINITY;
    else v = std::ldexp((float)(m | 1024), (int)e - 25);
    return s ? -v : v;
}

bool BodyData::load(const std::string &jsonPath, const std::string &binPath) {
    ok = false;
    ofJson j;
    try {
        std::ifstream f(jsonPath);
        if (!f) { error = "missing " + jsonPath; return false; }
        f >> j;
    } catch (std::exception &e) { error = std::string("bad json: ") + e.what(); return false; }
    try {
        W = j.at("W"); H = j.at("H"); every = j.at("every");
        tag = j.at("tag").get<std::string>();
        law = j.value("law", std::string());
        deadAt = j.at("dead_at").is_null() ? -1 : j.at("dead_at").get<long>();
        long nframes = j.at("nframes"), fb = j.at("frame_bytes");
        if (W * H != 576) { error = "W*H != 576"; return false; }
        // the layout must be exactly the one this reader knows (export-spec.md §3)
        static const char *want[] = {"n", "sha", "reservoir", "pool", "born", "died", "alive", "C", "B", "A",
                                     "active", "q", "sg", "h", "acts"};
        auto &lay = j.at("layout");
        if (lay.size() != 15) { error = "unknown layout"; return false; }
        int NU = 0, NE = 0;
        long size = 0;
        for (int k = 0; k < 15; ++k) {
            std::string nm = lay[k].at("name"), ty = lay[k].at("type");
            int cnt = lay[k].at("count");
            if (nm != want[k]) { error = "unknown layout field " + nm; return false; }
            int b = (ty == "Int32" || ty == "Float32") ? 4 : ty == "Float16" ? 2 : ty == "UInt8" ? 1 : 0;
            if (!b) { error = "unknown type " + ty; return false; }
            size += (long)b * cnt;
            if (nm == "active") NU = cnt;
            if (nm == "q") NE = cnt;
        }
        if (size != fb) { error = "frame_bytes mismatch"; return false; }
        auto &cir = j.at("circuit");
        names.clear(); kind.clear(); edges.clear();
        for (auto &s : cir.at("names")) names.push_back(s.get<std::string>());
        for (auto &s : cir.at("kind")) kind.push_back(s.get<std::string>()[0]);
        for (auto &e : cir.at("edges")) edges.push_back({e[0].get<int>() - 1, e[1].get<int>() - 1});
        if ((int)names.size() != NU || (int)edges.size() != NE) { error = "circuit size mismatch"; return false; }

        std::ifstream b(binPath, std::ios::binary);
        if (!b) { error = "missing " + binPath; return false; }
        std::vector<char> buf((std::istreambuf_iterator<char>(b)), std::istreambuf_iterator<char>());
        if ((long)buf.size() != nframes * fb) { error = "bin size mismatch"; return false; }
        frames.assign(nframes, BodyFrame());
        for (long i = 0; i < nframes; ++i) {
            const char *p = buf.data() + i * fb;
            BodyFrame &F = frames[i];
            auto rd = [&](void *dst, size_t n) { std::memcpy(dst, p, n); p += n; };
            int32_t i32; float f32; uint8_t u8;
            rd(&i32, 4); F.n = i32;
            p += 32; // sha
            rd(&f32, 4); F.reservoir = f32;
            rd(&F.pool[0], 4); rd(&F.pool[1], 4);
            rd(&i32, 4); F.born = i32; rd(&i32, 4); F.died = i32;
            rd(&u8, 1); F.alive = u8 != 0;
            rd(F.C.data(), 576);
            uint16_t hv[576];
            rd(hv, 1152); for (int k = 0; k < 576; ++k) F.B[k] = half2float(hv[k]);
            rd(hv, 1152); for (int k = 0; k < 576; ++k) F.A[k] = half2float(hv[k]);
            F.active.resize(NU); rd(F.active.data(), NU);
            F.q.resize(NE); F.sg.resize(NE); F.h.resize(NE);
            rd(F.q.data(), 4 * NE); rd(F.sg.data(), 4 * NE); rd(F.h.data(), 4 * NE);
            rd(F.acts, 2);
            if (i > 0 && F.n <= frames[i - 1].n) { error = "frames out of order"; return false; }
        }
    } catch (std::exception &e) { error = std::string("bad header: ") + e.what(); return false; }
    ok = !frames.empty();
    if (!ok) error = "no frames";
    return ok;
}

int BodyData::frameAt(double s) const {
    if (frames.empty()) return -1;
    int lo = 0, hi = (int)frames.size() - 1;
    if (s <= frames[0].n) return 0;
    while (lo < hi) {
        int mid = (lo + hi + 1) / 2;
        if (frames[mid].n <= s) lo = mid; else hi = mid - 1;
    }
    return lo;
}

// ---------------------------------------------------------------- look
ofJson Look::toJson() const {
    ofJson j;
#define P(k) j[#k] = k;
    P(mode) P(renderScale) P(follow) P(span) P(interp) P(wC) P(wB) P(wA) P(iso) P(soft) P(glow) P(shimmer)
    P(gridLines) P(gap) P(hueSrc) P(hueShift) P(sat) P(val) P(hazeHue) P(torR) P(torr) P(torH) P(spin) P(tilt)
    P(dist) P(subdiv) P(wire) P(solid) P(circuit) P(labels) P(edgeW) P(hudAlpha)
    P(theme) P(flowForce) P(flowSpeed) P(flowVort) P(flowFade) P(flowBuoy) P(flowVisc) P(flowSource)
#undef P
    j["hueFixed"] = {hueFixed[0], hueFixed[1]};
    return j;
}

void Look::fromJson(const ofJson &j) {
#define G(k) if (j.contains(#k)) k = j[#k].get<decltype(k)>();
    G(mode) G(renderScale) G(follow) G(span) G(interp) G(wC) G(wB) G(wA) G(iso) G(soft) G(glow) G(shimmer)
    G(gridLines) G(gap) G(hueSrc) G(hueShift) G(sat) G(val) G(hazeHue) G(torR) G(torr) G(torH) G(spin) G(tilt)
    G(dist) G(subdiv) G(wire) G(solid) G(circuit) G(labels) G(edgeW) G(hudAlpha)
    G(theme) G(flowForce) G(flowSpeed) G(flowVort) G(flowFade) G(flowBuoy) G(flowVisc) G(flowSource)
#undef G
    if (j.contains("hueFixed") && j["hueFixed"].size() == 2) {
        hueFixed[0] = j["hueFixed"][0]; hueFixed[1] = j["hueFixed"][1];
    }
    mode = ofClamp(mode, 0, 5);
    theme = ofClamp(theme, 0, 2);
    subdiv = ofClamp(subdiv, 1, 8);
    renderScale = ofClamp(renderScale, 0.4f, 1.0f);
}

// ---------------------------------------------------------------- view
void BodyView::setup(const std::string &dataDir) {
    const char *tags[2] = {"L2", "L2SF"};
    for (int c = 0; c < 2; ++c) {
        std::string base = dataDir + "/body-669-" + tags[c];
        if (!data[c].load(base + ".json", base + ".bin"))
            ofLogError("BodyView") << tags[c] << ": " << data[c].error;
        else
            ofLogNotice("BodyView") << tags[c] << ": " << data[c].frames.size() << " frames, dead_at " << data[c].deadAt;
        ofTextureData td;
        td.width = 24; td.height = 24;
        td.glInternalFormat = GL_RGBA32F;
        td.textureTarget = GL_TEXTURE_2D;
        tex[c].allocate(td);
        tex[c].setTextureMinMagFilter(GL_NEAREST, GL_NEAREST);
        px[c].allocate(24, 24, OF_PIXELS_RGBA);
        px[c].set(0);
        for (int k = 0; k < 576; ++k) curC[c][k] = curB[c][k] = curA[c][k] = 0;
    }
    body.load("shaders/body");
    looksDir = ofToDataPath("looks", true);
    ofDirectory::createDirectory(looksDir, false, true);
    std::string def = looksDir + "/default.json";
    if (ofFile::doesFileExist(def, false)) {
        try { look.fromJson(ofLoadJson(def)); status = "loaded default.json"; } catch (...) { status = "default.json unreadable"; }
    }
    refreshLookFiles();
}

void BodyView::update(const double s[2]) {
    for (int c = 0; c < 2; ++c) {
        const BodyData &D = data[c];
        if (!D.ok) continue;
        double sc = scrub ? scrubN[c] : s[c];
        int i0 = D.frameAt(sc), i1 = std::min(i0 + 1, (int)D.frames.size() - 1);
        const BodyFrame &F0 = D.frames[i0], &F1 = D.frames[i1];
        float t = 0;
        if (look.interp && i1 > i0) t = (float)ofClamp((sc - F0.n) / double(F1.n - F0.n), 0.0, 1.0);
        cur[c] = i0;
        double sx[2] = {0, 0}, cx[2] = {0, 0}, tot = 0;
        for (int k = 0; k < 576; ++k) {
            curC[c][k] = F0.C[k] ? 1.0f : 0.0f;          // the constituents are never blended
            curB[c][k] = F0.B[k] + (F1.B[k] - F0.B[k]) * t;
            curA[c][k] = F0.A[k] + (F1.A[k] - F0.A[k]) * t;
            if (F0.C[k]) {
                int x = k % 24, y = k / 24;
                double ax = TWO_PI * (x + 0.5) / 24, ay = TWO_PI * (y + 0.5) / 24;
                sx[0] += std::sin(ax); cx[0] += std::cos(ax);
                sx[1] += std::sin(ay); cx[1] += std::cos(ay);
                tot += 1;
            }
            px[c][k * 4 + 0] = curC[c][k];
            px[c][k * 4 + 1] = curB[c][k];
            px[c][k * 4 + 2] = curA[c][k];
            px[c][k * 4 + 3] = 0;
        }
        tex[c].loadData(px[c]);
        // centre of the body on the torus (circular mean); without a body, or with follow off, hold still
        for (int a = 0; a < 2; ++a) {
            double target = off[c][a];
            if (!look.follow) target = 12;
            else if (tot > 0 && (sx[a] * sx[a] + cx[a] * cx[a]) > 1e-6) {
                double ang = std::atan2(sx[a], cx[a]);
                if (ang < 0) ang += TWO_PI;
                target = ang / TWO_PI * 24;
            }
            if (!offInit[c]) { off[c][a] = (float)target; continue; }
            double d = target - off[c][a];
            d -= 24 * std::round(d / 24);
            off[c][a] += (float)(d * 0.04);
            off[c][a] = std::fmod(off[c][a] + 24.0f, 24.0f);
        }
        offInit[c] = true;
    }
}

ofRectangle BodyView::bodyRect(int c, float w, float h) const {
    float aw = w * (1 - reserveFrac);
    float side = std::min(aw * 0.40f, h * 0.44f);
    float cx = aw * (c == 0 ? 0.25f : 0.75f), cy = h * 0.31f;
    return ofRectangle(cx - side / 2, cy - side / 2, side, side);
}

ofRectangle BodyView::circuitRect(int c, float w, float h) const {
    ofRectangle b = bodyRect(c, w, h);
    if (look.mode == 3) {
        float bw = std::min(w * (1 - reserveFrac) * 0.44f, h * 0.9f), bh = h * 0.50f;
        return ofRectangle(b.getCenter().x - bw / 2, h * 0.19f, bw, bh);
    }
    return ofRectangle(b.x, b.getBottom() + h * 0.015f, b.width, h * 0.13f);
}

float BodyView::sample(int c, float x, float y) const {
    // cubic B-spline over cell centres, wrapping on the torus; returns the weighted density
    float qx = x - 0.5f, qy = y - 0.5f;
    int ix = (int)std::floor(qx), iy = (int)std::floor(qy);
    float fx = qx - ix, fy = qy - iy;
    auto wts = [](float f, float w[4]) {
        float f2 = f * f, f3 = f2 * f;
        w[0] = (1 - f) * (1 - f) * (1 - f) / 6; w[1] = (3 * f3 - 6 * f2 + 4) / 6;
        w[2] = (-3 * f3 + 3 * f2 + 3 * f + 1) / 6; w[3] = f3 / 6;
    };
    float wx[4], wy[4];
    wts(fx, wx); wts(fy, wy);
    float d = 0;
    for (int j = 0; j < 4; ++j) for (int i = 0; i < 4; ++i) {
        int xx = ((ix + i - 1) % 24 + 24) % 24, yy = ((iy + j - 1) % 24 + 24) % 24;
        int k = yy * 24 + xx;
        d += wx[i] * wy[j] * (look.wC * curC[c][k] + look.wB * curB[c][k]);
    }
    return d;
}

static ofFloatColor hsvF(float h, float s, float v) {
    h = h - std::floor(h);
    ofFloatColor k;
    auto ch = [&](float n) { float kk = std::fmod(n + h * 6, 6.0f); return v * (1 - s * std::max(0.0f, std::min({kk, 4 - kk, 1.0f}))); };
    return ofFloatColor(ch(5), ch(3), ch(1));
}

void BodyView::drawScene(float w, float h, float ptScale, const float alive[2], const float hue[2], const bool mis[2], bool stale) {
    ofClear(5, 6, 12, 255); // = the shader's background after its gamma
    if (look.mode == 3) return; // the network is drawn by drawOverlay
    for (int c = 0; c < 2; ++c) {
        if (!data[c].ok) continue;
        float hu = (look.hueSrc == 0 ? hue[c] : look.hueFixed[c]) + look.hueShift;
        ofRectangle r = bodyRect(c, w, h);
        if (look.mode == 4) { drawTorus(c, r, alive[c], hu); continue; }
        if (look.mode == 2 || look.mode == 5) r.scaleFromCenter(1.3f);
        if (look.mode == 5) {
            // the fluid's density (it started from the body picture and was carried by the fluid)
            if (!flowReady) continue;
            ofPushStyle();
            ofDisableBlendMode(); // the density's colour replaces the dark ground inside the square
            ofSetColor(255);
            fluid[c].draw(r.x, r.getBottom(), r.width, -r.height);
            ofEnableBlendMode(OF_BLENDMODE_ALPHA);
            ofNoFill();
            ofSetColor(140, 150, 180, 40);
            ofDrawRectangle(r);
            ofPopStyle();
            continue;
        }
        float span = look.span * (look.mode == 2 ? 1.3f : 1.0f);
        quad.clear();
        quad.setMode(OF_PRIMITIVE_TRIANGLE_FAN);
        quad.addVertex({r.x, r.y, 0}); quad.addTexCoord({0, 0});
        quad.addVertex({r.getRight(), r.y, 0}); quad.addTexCoord({1, 0});
        quad.addVertex({r.getRight(), r.getBottom(), 0}); quad.addTexCoord({1, 1});
        quad.addVertex({r.x, r.getBottom(), 0}); quad.addTexCoord({0, 1});
        setBodyUniforms(c, look.mode, r.width, span, alive[c], hu, mis[c], stale);
        quad.draw();
        body.end();
    }
}

// begins the body shader with this life's uniforms (the caller draws the quad and ends it)
void BodyView::setBodyUniforms(int c, int mode, float pxW, float span, float alive, float hu, bool mis, bool stale) {
    body.begin();
    body.setUniformTexture("uTex", tex[c], 0);
    body.setUniform1i("uMode", mode);
    body.setUniform2f("uOff", off[c][0], off[c][1]);
    body.setUniform1f("uSpan", span);
    body.setUniform1f("uPx", pxW);
    body.setUniform1f("uWC", look.wC); body.setUniform1f("uWB", look.wB); body.setUniform1f("uWA", look.wA);
    body.setUniform1f("uIso", look.iso); body.setUniform1f("uSoft", look.soft);
    body.setUniform1f("uGlow", look.glow); body.setUniform1f("uShimmer", look.shimmer);
    body.setUniform1f("uGridLines", look.gridLines); body.setUniform1f("uGap", look.gap);
    body.setUniform1f("uHue", hu); body.setUniform1f("uSat", look.sat); body.setUniform1f("uVal", look.val);
    body.setUniform1f("uHaze", look.hazeHue);
    body.setUniform1f("uAlive", alive);
    body.setUniform1f("uTime", ofGetElapsedTimef());
    body.setUniform1f("uMis", mis ? 1.0f : 0.0f);
    body.setUniform1f("uStale", stale ? 1.0f : 0.0f);
    body.setUniform1f("uSrc", look.flowSource);
}

// ---------------------------------------------------------------- flow (ofxFlowTools, mode 5)
// The fluid is clothing, not data: its own motion (advection, vorticity, buoyancy) is the simulation's. What comes
// from the life is only the source (the body picture: C, B, A of the recomputed reference, coloured as in the field)
// and the push (optical flow of that picture between frames, i.e. where the body changed or moved on the torus).
static const int FLOW_SIM = 128, FLOW_DEN = 256;

void BodyView::setupFlow() {
    for (int c = 0; c < 2; ++c) {
        flowSrc[c].allocate(FLOW_DEN, FLOW_DEN, GL_RGBA32F);
        flowSrc[c].begin(); ofClear(0, 0, 0, 255); flowSrc[c].end();
        optical[c].setup(FLOW_SIM, FLOW_SIM);
        bridge[c].setup(FLOW_SIM, FLOW_SIM, FLOW_DEN, FLOW_DEN);
        fluid[c].setup(FLOW_SIM, FLOW_SIM, FLOW_DEN, FLOW_DEN);
    }
    flowReady = true;
}

void BodyView::updateFlow(float dt, const float alive[2], const float hue[2], const bool mis[2], bool stale) {
    if (look.mode != 5) return;
    if (!flowReady) setupFlow();
    dt = ofClamp(dt, 1.0f / 240, 1.0f / 15);
    for (int c = 0; c < 2; ++c) {
        if (!data[c].ok) continue;
        float hu = (look.hueSrc == 0 ? hue[c] : look.hueFixed[c]) + look.hueShift;
        flowSrc[c].begin();
        ofClear(0, 0, 0, 255);
        quad.clear();
        quad.setMode(OF_PRIMITIVE_TRIANGLE_FAN);
        // upside down here and drawn flipped below: the body faces as in the field, and warm smoke rises
        quad.addVertex({0, 0, 0}); quad.addTexCoord({0, 1});
        quad.addVertex({(float)FLOW_DEN, 0, 0}); quad.addTexCoord({1, 1});
        quad.addVertex({(float)FLOW_DEN, (float)FLOW_DEN, 0}); quad.addTexCoord({1, 0});
        quad.addVertex({0, (float)FLOW_DEN, 0}); quad.addTexCoord({0, 0});
        setBodyUniforms(c, 3, FLOW_DEN, look.span * 1.3f, alive[c], hu, mis[c], stale);
        quad.draw();
        body.end();
        flowSrc[c].end();

        optical[c].setStrength(look.flowForce);
        optical[c].setInput(flowSrc[c].getTexture());
        optical[c].update();
        bridge[c].setVelocity(optical[c].getVelocity());
        bridge[c].setDensity(flowSrc[c].getTexture());
        bridge[c].update(dt);
        fluid[c].setSpeed(look.flowSpeed);
        fluid[c].setVorticity(look.flowVort);
        fluid[c].setDissipationDen(look.flowFade);
        fluid[c].setDissipationVel(0.1f);
        fluid[c].setViscosityVel(look.flowVisc);
        fluid[c].setBuoyancyWeight(look.flowBuoy);
        fluid[c].addVelocity(bridge[c].getVelocity());
        fluid[c].addDensity(bridge[c].getDensity());              // where the picture moved
        fluid[c].pour(flowSrc[c].getTexture(), look.flowSource * dt * 30.0f); // the body itself, steadily
        fluid[c].addTemperature(bridge[c].getTemperature());
        fluid[c].update(dt);
    }
}

void BodyView::drawTorus(int c, const ofRectangle &rr, float alive, float hue) {
    ofRectangle r = rr;
    r.scaleFromCenter(1.25f, 1.12f);
    // ofCamera's viewport counts from the bottom inside an fbo
    r.y = ofGetCurrentViewport().height - r.y - r.height;
    const int N = 24 * look.subdiv;
    const float R = look.torR, rt = look.torr;
    std::vector<glm::vec3> P(N * N), T(N * N);
    std::vector<float> D(N * N), Am(N * N);
    // the body's centre faces outward at theta = 0, phi = 0
    for (int j = 0; j < N; ++j) for (int i = 0; i < N; ++i) {
        float x = off[c][0] + (float)i / look.subdiv, y = off[c][1] + (float)j / look.subdiv;
        float d = sample(c, x, y);
        float th = TWO_PI * i / N, ph = TWO_PI * j / N;
        float rad = rt * (1 + look.torH * std::min(2.0f, d));
        glm::vec3 tube(std::cos(ph) * std::cos(th), std::cos(ph) * std::sin(th), std::sin(ph));
        P[j * N + i] = glm::vec3(R * std::cos(th), R * std::sin(th), 0) + rad * tube;
        T[j * N + i] = tube;
        D[j * N + i] = d;
        int xx = ((int)std::floor(x) % 24 + 24) % 24, yy = ((int)std::floor(y) % 24 + 24) % 24;
        Am[j * N + i] = curA[c][yy * 24 + xx];
    }
    torus.clear();
    torus.setMode(OF_PRIMITIVE_TRIANGLES);
    glm::vec3 L = glm::normalize(glm::vec3(0.45f, -0.35f, 0.8f));
    ofFloatColor col = hsvF(hue, look.sat * (0.35f + 0.65f * alive), look.val);
    ofFloatColor haze = hsvF(hue + look.hazeHue, 0.5f, 0.6f);
    ofFloatColor dark(0.11f, 0.12f, 0.17f);
    for (int j = 0; j < N; ++j) for (int i = 0; i < N; ++i) {
        int k = j * N + i;
        glm::vec3 du = P[j * N + (i + 1) % N] - P[j * N + (i + N - 1) % N];
        glm::vec3 dv = P[((j + 1) % N) * N + i] - P[((j + N - 1) % N) * N + i];
        glm::vec3 n = glm::normalize(glm::cross(du, dv));
        if (glm::dot(n, T[k]) < 0) n = -n;
        float lam = 0.22f + 0.78f * std::max(0.0f, glm::dot(n, L));
        float bodyAmt = ofClamp((D[k] - (look.iso - look.soft)) / std::max(0.02f, 2 * look.soft), 0, 1);
        ofFloatColor cc = dark;
        float a = ofClamp(Am[k] * look.wA, 0, 1);
        cc.r += haze.r * a * 0.35f; cc.g += haze.g * a * 0.35f; cc.b += haze.b * a * 0.35f;
        cc.lerp(col, bodyAmt * (0.25f + 0.75f * alive));
        cc *= lam;
        float g = look.glow * 0.25f * std::min(1.0f, D[k]);
        cc.r += col.r * g; cc.g += col.g * g; cc.b += col.b * g;
        cc.a = 1;
        torus.addVertex(P[k]);
        torus.addColor(cc);
    }
    for (int j = 0; j < N; ++j) for (int i = 0; i < N; ++i) {
        int a = j * N + i, b = j * N + (i + 1) % N, cI = ((j + 1) % N) * N + i, d = ((j + 1) % N) * N + (i + 1) % N;
        torus.addIndex(a); torus.addIndex(b); torus.addIndex(d);
        torus.addIndex(a); torus.addIndex(d); torus.addIndex(cI);
    }
    ofCamera cam;
    cam.setNearClip(0.05f);
    cam.setFarClip(100);
    cam.setFov(40);
    float yaw = ofGetElapsedTimef() * look.spin * TWO_PI, pitch = look.tilt; // yaw 0 looks at the body (theta = 0)
    cam.setPosition(look.dist * std::cos(pitch) * std::cos(yaw), look.dist * std::cos(pitch) * std::sin(yaw), look.dist * std::sin(pitch));
    cam.lookAt(glm::vec3(0), glm::vec3(0, 0, 1));
    ofPushStyle();
    ofEnableDepthTest();
    cam.begin(r);

    if (look.solid) torus.draw();
    if (look.wire) {
        // the cell boundaries of the torus, slightly outside the surface
        ofMesh lines;
        lines.setMode(OF_PRIMITIVE_LINES);
        ofFloatColor lc = col;
        lc.a = 0.28f;
        auto at = [&](int i, int j) { int k = ((j % N + N) % N) * N + ((i % N + N) % N); return P[k] + T[k] * 0.004f; };
        int s = look.subdiv;
        for (int cell = 0; cell < 24; ++cell)
            for (int t = 0; t < N; ++t) {
                lines.addVertex(at(cell * s, t)); lines.addColor(lc);
                lines.addVertex(at(cell * s, t + 1)); lines.addColor(lc);
                lines.addVertex(at(t, cell * s)); lines.addColor(lc);
                lines.addVertex(at(t + 1, cell * s)); lines.addColor(lc);
            }
        ofEnableBlendMode(OF_BLENDMODE_ADD);
        lines.draw();
        ofEnableBlendMode(OF_BLENDMODE_ALPHA);
    }
    cam.end();
    ofDisableDepthTest();
    ofPopStyle();
}

// ---------------------------------------------------------------- circuit network (ImGui draw list, in points)
static ImU32 col32(ofFloatColor c, float a) { return ImGui::ColorConvertFloat4ToU32(ImVec4(c.r, c.g, c.b, a)); }

void BodyView::drawNetwork(ImDrawList *dl, int c, const ofRectangle &r, float hue, bool big) {
    const BodyData &D = data[c];
    if (!D.ok || cur[c] < 0) return;
    const BodyFrame &F = D.frames[cur[c]];
    int nu = (int)D.names.size();
    std::vector<ImVec2> pos(nu);
    std::vector<int> R, C, M;
    for (int u = 0; u < nu; ++u) (D.kind[u] == 'R' ? R : D.kind[u] == 'C' ? C : M).push_back(u);
    bool vertical = r.height > r.width * 0.6f;
    for (size_t i = 0; i < R.size(); ++i) {
        float t = R.size() > 1 ? (float)i / (R.size() - 1) : 0.5f;
        pos[R[i]] = vertical ? ImVec2(r.x + r.width * 0.10f, r.y + r.height * (0.08f + 0.84f * t))
                             : ImVec2(r.x + r.width * (0.06f + 0.58f * t), r.y + r.height * 0.22f);
    }
    for (size_t i = 0; i < C.size(); ++i) {
        float t = C.size() > 1 ? (float)i / (C.size() - 1) : 0.5f;
        pos[C[i]] = vertical ? ImVec2(r.x + r.width * 0.45f, r.y + r.height * (0.30f + 0.40f * t))
                             : ImVec2(r.x + r.width * (0.16f + 0.30f * t), r.y + r.height * 0.80f);
    }
    for (size_t i = 0; i < M.size(); ++i) {
        float t = M.size() > 1 ? (float)i / (M.size() - 1) : 0.5f;
        pos[M[i]] = vertical ? ImVec2(r.x + r.width * 0.88f, r.y + r.height * (0.30f + 0.40f * t))
                             : ImVec2(r.x + r.width * 0.86f, r.y + r.height * (0.25f + 0.50f * t));
    }
    // on the light theme the picture is paper, so the lines are ink: darker and more saturated
    ofFloatColor col = light ? hsvF(hue, std::min(1.0f, look.sat + 0.15f), 0.55f * std::min(1.0f, look.val)) : hsvF(hue, look.sat, look.val);
    ofFloatColor warm = light ? hsvF(hue + 0.12f, 0.75f, 0.62f) : hsvF(hue + 0.12f, 0.55f, 1.0f);
    ofFloatColor grey = light ? ofFloatColor(0.36f, 0.38f, 0.43f) : ofFloatColor(0.55f, 0.58f, 0.64f);
    ofFloatColor offFill = light ? ofFloatColor(0.96f, 0.955f, 0.94f) : ofFloatColor(0.06f, 0.07f, 0.10f);
    float unitR = big ? 10.0f : 5.5f, ew = look.edgeW * (big ? 1.6f : 1.0f);
    // edges: width and brightness from q, a thin warm thread from sg, dots for h (all 0..4)
    for (size_t k = 0; k < D.edges.size(); ++k) {
        int a = D.edges[k][0], b = D.edges[k][1];
        int q = F.q[k], sg = F.sg[k], hh = F.h[k];
        ImVec2 p0 = pos[a], p1 = pos[b];
        float alpha = (light ? 0.18f : 0.10f) + 0.16f * q;
        if (a == b) {
            ImVec2 cc(p0.x - unitR * 1.6f, p0.y);
            dl->AddCircle(cc, unitR * 1.1f, col32(col, alpha), 32, ew * (0.6f + 0.5f * q));
            if (sg) dl->AddCircle(cc, unitR * 1.1f, col32(warm, 0.2f * sg), 32, ew * 0.8f);
            continue;
        }
        float dx = (p1.x - p0.x) * 0.45f, dy = vertical ? 0 : (p1.y - p0.y) * 0.25f;
        ImVec2 c0(p0.x + dx, p0.y + dy), c1(p1.x - dx, p1.y - dy);
        dl->AddBezierCubic(p0, c0, c1, p1, col32(col, alpha), ew * (0.6f + 0.55f * q), 40);
        if (sg) dl->AddBezierCubic(p0, c0, c1, p1, col32(warm, 0.18f + 0.15f * sg), ew * 0.9f, 40);
        for (int d = 0; d < hh; ++d) {
            float t = 0.42f + 0.06f * d, u = 1 - t;
            ImVec2 m(u * u * u * p0.x + 3 * u * u * t * c0.x + 3 * u * t * t * c1.x + t * t * t * p1.x,
                     u * u * u * p0.y + 3 * u * u * t * c0.y + 3 * u * t * t * c1.y + t * t * t * p1.y);
            dl->AddCircleFilled(m, ew * 1.6f, col32(grey, 0.85f), 12);
        }
    }
    ImFont *font = ImGui::GetFont();
    float fs = big ? 15.0f : 12.0f;
    for (int u = 0; u < nu; ++u) {
        bool on = u < (int)F.active.size() && F.active[u];
        if (on) {
            for (int g = 3; g >= 1; --g) dl->AddCircleFilled(pos[u], unitR * (1 + 0.55f * g), col32(col, light ? 0.05f : 0.07f), 36);
            dl->AddCircleFilled(pos[u], unitR, col32(col, 0.95f), 36);
        } else {
            dl->AddCircleFilled(pos[u], unitR, col32(offFill, 0.95f), 36);
            dl->AddCircle(pos[u], unitR, col32(grey, 0.7f), 36, 1.2f);
        }
        // a motor whose patch acted (acts, after this step): an outer ring
        if (D.kind[u] == 'M') {
            int pi = (u == M[0]) ? 0 : 1;
            if (F.acts[pi]) dl->AddCircle(pos[u], unitR * 1.9f, col32(warm, 0.9f), 40, 1.6f);
        }
        if (look.labels) {
            ImVec2 tp = D.kind[u] == 'R' && vertical ? ImVec2(pos[u].x - unitR - fs * 1.4f, pos[u].y - fs * 0.5f)
                                                     : ImVec2(pos[u].x - fs * 0.5f, pos[u].y + unitR + 3);
            dl->AddText(font, fs, tp, col32(grey, 0.9f), D.names[u].c_str());
        }
    }
}

void BodyView::drawOverlay(float wPt, float hPt, const float hue[2]) {
    if (!(look.circuit || look.mode == 3)) return;
    ImDrawList *dl = ImGui::GetBackgroundDrawList();
    for (int c = 0; c < 2; ++c) {
        float hu = (look.hueSrc == 0 ? hue[c] : look.hueFixed[c]) + look.hueShift;
        ofRectangle r = circuitRect(c, wPt, hPt);
        drawNetwork(dl, c, r, hu, look.mode == 3);
    }
}

// ---------------------------------------------------------------- panel
void BodyView::refreshLookFiles() {
    lookFiles.clear();
    ofDirectory d(looksDir);
    d.allowExt("json");
    d.listDir();
    d.sort();
    for (auto &f : d) lookFiles.push_back(f.getBaseName());
}

static bool sliderF(const char *label, float *v, float lo, float hi, const char *fmt = "%.2f") {
    return ImGui::SliderFloat(label, v, lo, hi, fmt);
}

void BodyView::panel(bool *open) {
    ImGui::SetNextWindowPos(ImVec2(ImGui::GetIO().DisplaySize.x - 14, 14), ImGuiCond_Always, ImVec2(1, 0));
    ImGui::SetNextWindowSizeConstraints(ImVec2(330, 120), ImVec2(330, ImGui::GetIO().DisplaySize.y - 28));
    ImGui::SetNextWindowSize(ImVec2(330, ImGui::GetIO().DisplaySize.y - 28), ImGuiCond_FirstUseEver);
    if (!ImGui::Begin("見せ方", open, ImGuiWindowFlags_NoMove)) { ImGui::End(); return; }
    static const char *modes[] = {"光（v1 の一式）", "升目", "場（なめらか）", "回路の網", "トーラス（立体）", "流れ（流体）"};
    ImGui::PushItemWidth(-128);
    ImGui::PushFont(nullptr, 14.0f);
    ImGui::TextDisabled("画面");
    ImGui::RadioButton("暗い", &look.theme, 0); ImGui::SameLine();
    ImGui::RadioButton("明るい", &look.theme, 1); ImGui::SameLine();
    ImGui::RadioButton("Mac に合わせる", &look.theme, 2);
    ImGui::SetItemTooltip("システム設定の外観（ライト／ダーク）に合わせる。キー l で暗い↔明るい");
    ImGui::Combo("見せ方", &look.mode, modes, 6);
    sliderF("絵の解像度", &look.renderScale, 0.4f, 1.0f);
    ImGui::SetItemTooltip("文字はいつも鮮明。重いときに絵だけ下げる");
    for (int c = 0; c < 2; ++c)
        if (!data[c].ok) ImGui::TextColored(ImVec4(1, 0.45f, 0.4f, 1), "体の値を読めない（%s）: %s", c ? "L2SF" : "L2", data[c].error.c_str());

    bool body = look.mode == 1 || look.mode == 2 || look.mode == 4 || look.mode == 5;
    if (ImGui::CollapsingHeader("歩", ImGuiTreeNodeFlags_DefaultOpen)) {
        ImGui::Checkbox("絵の歩を手で選ぶ", &scrub);
        ImGui::SetItemTooltip("絵だけが変わる。音と HUD は推定の歩のまま");
        ImGui::BeginDisabled(!scrub);
        for (int c = 0; c < 2; ++c) {
            if (!data[c].ok) continue;
            int last = data[c].frames.back().n;
            int v = (int)scrubN[c];
            if (ImGui::SliderInt(c ? "試-2 の歩" : "試-1 の歩", &v, 0, last)) scrubN[c] = (float)v;
        }
        ImGui::EndDisabled();
        ImGui::Checkbox("B と A をフレームの間でなめらかに", &look.interp);
        ImGui::SetItemTooltip("フレームは 6 歩ごと。C と回路はなめらかにしない");
    }
    if (ImGui::CollapsingHeader("形", ImGuiTreeNodeFlags_DefaultOpen)) {
        ImGui::BeginDisabled(!body);
        ImGui::Checkbox("体の中心を追う", &look.follow);
        sliderF("見る広さ（升）", &look.span, 6, 24, "%.1f");
        sliderF("C の重み", &look.wC, 0, 1.5f);
        ImGui::SetItemTooltip("C: 体の升（構成要素）");
        sliderF("B の重み", &look.wB, 0, 1.5f);
        ImGui::SetItemTooltip("B: 結合物質");
        sliderF("A の濃さ", &look.wA, 0, 10, "%.1f");
        ImGui::SetItemTooltip("A: まわりの物質");
        ImGui::BeginDisabled(look.mode == 1);
        sliderF("輪郭の高さ", &look.iso, 0.05f, 1.2f);
        sliderF("輪郭のやわらかさ", &look.soft, 0.01f, 0.5f);
        sliderF("にじみの光", &look.glow, 0, 2);
        sliderF("揺らぎ", &look.shimmer, 0, 1);
        ImGui::EndDisabled();
        sliderF("升の線", &look.gridLines, 0, 1);
        ImGui::BeginDisabled(look.mode != 1);
        sliderF("升のすき間", &look.gap, 0, 0.5f);
        ImGui::EndDisabled();
        ImGui::EndDisabled();
    }
    if (ImGui::CollapsingHeader("色", ImGuiTreeNodeFlags_DefaultOpen)) {
        static const char *srcs[] = {"その歩の基準の sha（v1 と同じ）", "固定"};
        ImGui::Combo("色相のもと", &look.hueSrc, srcs, 2);
        if (look.hueSrc == 1) {
            sliderF("試-1 の色相", &look.hueFixed[0], 0, 1);
            sliderF("試-2 の色相", &look.hueFixed[1], 0, 1);
        }
        sliderF("色相をずらす", &look.hueShift, -0.5f, 0.5f);
        sliderF("彩度", &look.sat, 0, 1);
        sliderF("明るさ", &look.val, 0.2f, 1.5f);
        sliderF("A の色（色相の差）", &look.hazeHue, 0, 1);
    }
    if (look.mode == 5 && ImGui::CollapsingHeader("流れ", ImGuiTreeNodeFlags_DefaultOpen)) {
        ImGui::TextDisabled("体の絵（場と同じ C・B・A）を流体に注ぎ、絵が変わった\nところ（光学流）で押す。渦・浮力・広がりは流体の\nシミュレーションの動きで、命の値ではない。");
        sliderF("注ぐ量", &look.flowSource, 0, 1.5f);
        sliderF("押す強さ（光学流）", &look.flowForce, 0.1f, 10, "%.1f");
        sliderF("流れの速さ", &look.flowSpeed, 0, 1);
        sliderF("渦", &look.flowVort, 0, 1);
        sliderF("ねばり", &look.flowVisc, 0, 1);
        sliderF("浮力", &look.flowBuoy, 0, 1);
        sliderF("消え方", &look.flowFade, 0, 1);
        if (ImGui::Button("流体を空にする")) for (int c = 0; c < 2; ++c) if (flowReady) { fluid[c].reset(); bridge[c].reset(); optical[c].reset(); }
    }
    if (look.mode == 4 && ImGui::CollapsingHeader("トーラス", ImGuiTreeNodeFlags_DefaultOpen)) {
        sliderF("輪の半径", &look.torR, 0.5f, 1.6f);
        sliderF("管の半径", &look.torr, 0.1f, 0.8f);
        sliderF("体の盛り上がり", &look.torH, 0, 1.5f);
        ImGui::SliderInt("なめらかさ", &look.subdiv, 1, 8);
        sliderF("回る速さ", &look.spin, -0.3f, 0.3f, "%.3f");
        sliderF("見下ろす角", &look.tilt, -1.4f, 1.4f);
        sliderF("距離", &look.dist, 1.5f, 8, "%.1f");
        ImGui::Checkbox("面", &look.solid); ImGui::SameLine();
        ImGui::Checkbox("升の線", &look.wire);
    }
    if (ImGui::CollapsingHeader("回路", ImGuiTreeNodeFlags_DefaultOpen)) {
        ImGui::BeginDisabled(look.mode == 3);
        ImGui::Checkbox("体の下に回路を出す", &look.circuit);
        ImGui::EndDisabled();
        ImGui::Checkbox("名前", &look.labels);
        sliderF("線の太さ", &look.edgeW, 0.3f, 3);
        ImGui::TextDisabled("塗った丸 = active。線の太さと明るさ = q、\n暖色の細い線 = sg、点の数 = h（どれも 0〜4）。\nm の外の輪 = その区画が動いた（acts）");
    }
    if (ImGui::CollapsingHeader("HUD")) sliderF("HUD の濃さ", &look.hudAlpha, 0, 1);
    if (ImGui::CollapsingHeader("保存", ImGuiTreeNodeFlags_DefaultOpen)) {
        static char buf[64] = "mine";
        ImGui::InputText("名前", buf, sizeof buf);
        std::string nm = buf;
        bool valid = !nm.empty() && std::all_of(nm.begin(), nm.end(), [](char ch) { return std::isalnum((unsigned char)ch) || ch == '-' || ch == '_'; });
        ImGui::BeginDisabled(!valid);
        if (ImGui::Button("保存する")) {
            ofSavePrettyJson(looksDir + "/" + nm + ".json", look.toJson());
            status = "saved looks/" + nm + ".json";
            refreshLookFiles();
        }
        ImGui::EndDisabled();
        ImGui::SameLine();
        if (ImGui::Button("起動時の形にする")) {
            ofSavePrettyJson(looksDir + "/default.json", look.toJson());
            status = "saved looks/default.json";
            refreshLookFiles();
        }
        ImGui::SameLine();
        if (ImGui::Button("初期値")) { look = Look(); status = "reset"; }
        if (!valid && !nm.empty()) ImGui::TextDisabled("名前は英数字と - _ だけ");
        if (!lookFiles.empty()) {
            ImGui::TextDisabled("読み込む");
            for (auto &f : lookFiles) {
                if (ImGui::Selectable(f.c_str(), false)) {
                    try { look.fromJson(ofLoadJson(looksDir + "/" + f + ".json")); status = "loaded " + f; std::snprintf(buf, sizeof buf, "%s", f.c_str()); }
                    catch (...) { status = f + " unreadable"; }
                }
            }
        }
        if (!status.empty()) ImGui::TextDisabled("%s", status.c_str());
    }
    ImGui::PopFont();
    ImGui::PopItemWidth();
    ImGui::End();
}
