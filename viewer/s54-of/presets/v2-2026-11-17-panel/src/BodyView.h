#pragma once
// S54 garden: the body of each life drawn from the recomputed reference (data/body-669-<tag>.{json,bin}, written by
// tools/export_body.jl every 6 steps and at the death step). These values are the reference recomputed on the Mac,
// not observations from the Pi: the trial matched the reference at every check, so they are the trial's state only
// as far as those checks go. Read only; nothing here writes into the lab (looks are saved under bin/data/looks/).
//
// The body: the constituents on the 24x24 torus (C != 0), the binding matter B, the ambient matter A around it, and
// the circuit (12 units, 22 edges; active per unit, q, sg, h per edge). No human form is imitated. The ways of
// showing it (grid, smooth field, network, torus in 3D) and their numbers are chosen on the panel.
#include "ofMain.h"
#include "imgui.h"
#include <array>

struct BodyFrame {
    int n = 0;
    float reservoir = 0, pool[2] = {0, 0};
    int born = 0, died = 0;
    bool alive = true;
    std::array<uint8_t, 576> C{};
    std::array<float, 576> B{}, A{};
    std::vector<uint8_t> active;
    std::vector<int> q, sg, h;
    uint8_t acts[2] = {0, 0};
};

struct BodyData {
    bool ok = false;
    std::string error, tag, law;
    int W = 24, H = 24, every = 6;
    long deadAt = -1;
    std::vector<BodyFrame> frames;
    std::vector<std::string> names;
    std::vector<char> kind;
    std::vector<std::array<int, 2>> edges; // 0-based from, to
    bool load(const std::string &jsonPath, const std::string &binPath);
    // index of the last frame with n <= s (frames are sorted by n)
    int frameAt(double s) const;
};

// everything the panel adjusts; saved as json
struct Look {
    int mode = 2;              // 0 glow (v1), 1 grid, 2 field, 3 network, 4 torus
    float renderScale = 1.0f;  // resolution of the picture (the text is always sharp)
    // view
    bool follow = true;        // keep the body's centre (circular mean on the torus) in the middle
    float span = 12.0f;        // cells across the view
    bool interp = true;        // blend B and A between frames (C and the circuit are never blended)
    // shape
    float wC = 0.7f, wB = 0.6f, wA = 2.5f; // weights of constituents, binding matter, ambient matter
    float iso = 0.42f, soft = 0.10f;
    float glow = 0.6f, shimmer = 0.25f, gridLines = 0.12f, gap = 0.14f;
    // colour
    int hueSrc = 0;            // 0 reference sha of the step (as v1), 1 fixed
    float hueFixed[2] = {0.36f, 0.58f};
    float hueShift = 0.0f, sat = 0.70f, val = 1.0f, hazeHue = 0.5f;
    // torus
    float torR = 1.0f, torr = 0.42f, torH = 0.70f, spin = 0.02f, tilt = 0.55f, dist = 5.2f;
    int subdiv = 4;
    bool wire = true, solid = true;
    // circuit
    bool circuit = true, labels = true;
    float edgeW = 1.0f;
    // hud
    float hudAlpha = 0.62f;
    ofJson toJson() const;
    void fromJson(const ofJson &j);
};

class BodyView {
public:
    void setup(const std::string &dataDir);
    BodyData data[2];
    Look look;
    // scrub: the picture shows a chosen step instead of the estimated one (sound and HUD keep the estimate)
    bool scrub = false;
    float scrubN[2] = {0, 0};

    // per frame: s = the step shown for each life, alive/hue/mismatch/stale from the app
    void update(const double s[2]);
    // draw the picture into the current target (fbo), size in its pixels; ptScale = pixels per ImGui point
    void drawScene(float w, float h, float ptScale, const float alive[2], const float hue[2], const bool mis[2], bool stale);
    // ImGui parts (call between gui.begin and gui.end)
    void drawOverlay(float wPt, float hPt, const float hue[2]); // circuit networks, drawn on the background list
    void panel(bool *open);
    int shownFrame(int c) const { return cur[c]; }
    std::string looksDir;
    float reserveFrac = 0; // share of the width on the right kept free for the panel
    ofRectangle bodyRect(int c, float w, float h) const; // in the units of w,h
    ofRectangle circuitRect(int c, float w, float h) const;

private:
    ofShader body;
    ofTexture tex[2];
    ofFloatPixels px[2];
    ofMesh quad, torus;
    float curC[2][576], curB[2][576], curA[2][576];
    int cur[2] = {-1, -1};
    float off[2][2] = {{12, 12}, {12, 12}};
    bool offInit[2] = {false, false};
    std::vector<std::string> lookFiles;
    std::string lookName = "mine";
    std::string status;
    void refreshLookFiles();
    void drawTorus(int c, const ofRectangle &r, float alive, float hue);
    void drawNetwork(ImDrawList *dl, int c, const ofRectangle &r, float hue, bool big);
    float sample(int c, float x, float y) const; // B-spline density on the torus (cells)
};
