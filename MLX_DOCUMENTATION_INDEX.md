# Cloud2Ground AI — MLX Documentation Index

**Last Updated:** 2026-07-18  
**Status:** POC Complete ✅

---

## 📚 Documentation Structure

This directory contains complete documentation for the MLX-Swift migration of Cloud2Ground AI.

### Start Here

👉 **[README_MLX.md](README_MLX.md)** — Overview, quick start, key features

---

## 📖 Core Documentation

### For Understanding What Was Accomplished

**[MLX_MIGRATION_COMPLETE.md](MLX_MIGRATION_COMPLETE.md)**
- Executive summary
- What we built
- Test results and proof
- Architecture diagrams
- Dependency reduction analysis
- **Read this to understand why this is a big deal**

### For Building and Maintaining

**[MLX_TECHNICAL_REFERENCE.md](MLX_TECHNICAL_REFERENCE.md)**
- Build process step-by-step
- Metal shader compilation (the hard part!)
- MLX-Swift API reference
- Bridge protocol specification
- Troubleshooting guide
- Common tasks
- **Read this when you need to build or debug**

### For Planning Production Release

**[MLX_PRODUCTION_PLAN.md](MLX_PRODUCTION_PLAN.md)**
- Phased roadmap (8 weeks to production)
- Feature porting checklist
- Packaging and installation plan
- Testing strategy
- Success metrics
- Risk management
- **Read this to plan next steps**

---

## 📁 Project Structure

```
Cloud2GroundAI/
│
├── README_MLX.md                    ← Start here
├── MLX_DOCUMENTATION_INDEX.md       ← This file
├── MLX_MIGRATION_COMPLETE.md        ← Success story
├── MLX_TECHNICAL_REFERENCE.md       ← Technical deep dive
├── MLX_PRODUCTION_PLAN.md           ← Roadmap
│
└── mlx_poc/                         ← Working proof of concept
    ├── SUCCESS.md                   ← POC test results
    ├── PROGRESS.md                  ← Build log
    ├── README.md                    ← Original staged plan
    │
    ├── c2g-mlx/                     ← Swift package
    │   ├── Package.swift
    │   ├── Sources/c2g-mlx/main.swift
    │   └── .build/arm64-apple-macosx/release/
    │       ├── c2g-mlx              ← Binary (44 MB)
    │       └── mlx.metallib         ← Shaders (3 MB)
    │
    ├── watch_mlx.sh                 ← Watcher daemon
    ├── bridge_test.sh               ← Test harness
    └── BUILD_METALLIB.sh            ← Metal compiler automation
```

---

## 🎯 Use Cases

### "I want to understand what this is"
→ Read **README_MLX.md**

### "I want to see the proof it works"
→ Read **MLX_MIGRATION_COMPLETE.md** → Test Results section

### "I need to build this"
→ Read **MLX_TECHNICAL_REFERENCE.md** → Build Process section

### "I need to fix a bug"
→ Read **MLX_TECHNICAL_REFERENCE.md** → Troubleshooting section

### "I want to plan production release"
→ Read **MLX_PRODUCTION_PLAN.md**

### "I'm 6 months in the future and forgot everything"
→ Read **README_MLX.md**, then **MLX_TECHNICAL_REFERENCE.md**

### "I want the nitty-gritty technical details"
→ Read **MLX_TECHNICAL_REFERENCE.md** cover to cover

### "I want to understand the architecture"
→ Read **MLX_MIGRATION_COMPLETE.md** → Architecture section

### "I need to debug the Metal shader compilation"
→ Read **MLX_TECHNICAL_REFERENCE.md** → Metal Shader Compilation section

### "I want to see the timeline and progress"
→ Read **mlx_poc/PROGRESS.md** and **mlx_poc/SUCCESS.md**

---

## 🔑 Key Concepts

### The Metal Library Mystery (SOLVED)

**Problem:** MLX needs `mlx.metallib` to run GPU operations, but SwiftPM doesn't build it for CLI tools.

**Solution:** Manual compilation pipeline automated in `BUILD_METALLIB.sh`

**Details:** See **MLX_TECHNICAL_REFERENCE.md** → Metal Shader Compilation

---

### The Bridge Protocol

**What:** File-based IPC between Claude (cloud) and Granite (local)

**Where:** `~/claude_bridge/_bridge/`

**Files:** `request.txt`, `response.txt`, `consumed.txt`, `processing.lock`

**Details:** See **MLX_TECHNICAL_REFERENCE.md** → Bridge Protocol Specification

---

### MLX-Swift 3.x API

**Key Macro:** `#huggingFaceLoadModelContainer(configuration:)`

**Main Types:** `ModelConfiguration`, `ModelContainer`, `ChatSession`

**Details:** See **MLX_TECHNICAL_REFERENCE.md** → MLX-Swift API Reference

---

## 🚀 Quick Commands

```bash
# Navigate to project
cd ~/Library/CloudStorage/ProtonDrive-acarlile@pm.me-folder/Carlano/Cloud2GroundAI/mlx_poc

# Build
cd c2g-mlx && swift build -c release && cd .. && ./BUILD_METALLIB.sh

# Run watcher
./watch_mlx.sh

# Test
./bridge_test.sh "test prompt"

# Direct test (bypass bridge)
echo "test" | .build/arm64-apple-macosx/release/c2g-mlx

# Switch model
export C2G_MLX_MODEL=mlx-community/granite-3.3-8b-instruct-8bit

# Check logs
tail -f ~/claude_bridge/_bridge/mlx.log

# Monitor watcher
ps aux | grep watch_mlx
```

---

## 📊 Project Status

### ✅ Phase 0: Proof of Concept
- [x] POC design
- [x] Build system
- [x] Metal shader compilation
- [x] Full loop testing
- [x] Documentation
- **Status:** **COMPLETE** (2026-07-18)

### 🔄 Phase 1: Feature Parity (Current)
- [ ] Port Ollama watcher features
- [ ] Daily dogfooding
- [ ] Model quality testing
- **Target:** Week 1-2

### 📋 Phase 2-5: Production
- [ ] Packaging & installation
- [ ] Skill integration
- [ ] Alpha testing
- [ ] Public release
- **Target:** 8 weeks total

**Full timeline in MLX_PRODUCTION_PLAN.md**

---

## 🎓 Learning Resources

### External Documentation

- **MLX-Swift Docs:** https://swiftpackageindex.com/ml-explore/mlx-swift/main/documentation/mlx
- **MLX-Swift-LM GitHub:** https://github.com/ml-explore/mlx-swift-lm
- **MLX-Swift Examples:** https://github.com/ml-explore/mlx-swift-examples
- **Granite Models:** https://huggingface.co/mlx-community?search_models=granite
- **Apple Metal Docs:** https://developer.apple.com/metal/

### Internal Documentation

- **All in this directory!** Start with README_MLX.md

---

## 🔧 Maintenance

### When to Update This Documentation

- **After major milestones** (phase completion)
- **When architecture changes**
- **When new bugs/solutions discovered**
- **Before going on vacation** (so you can pick back up)
- **When production released** (mark as v1.0)

### How to Update

1. Edit the relevant `.md` file
2. Update "Last Updated" date
3. Add to changelog section if major change
4. Commit with descriptive message

---

## 📝 Changelog

### 2026-07-18 — Initial Documentation
- Created all core documentation
- POC proven successful
- Ready for Phase 1

---

## 🤝 Contributing

When ready for external contributions:

1. Read **README_MLX.md** for overview
2. Read **MLX_TECHNICAL_REFERENCE.md** for technical details
3. Check **MLX_PRODUCTION_PLAN.md** for roadmap
4. Submit issues or PRs

---

## 📞 Support

### Internal (You)
- Check **MLX_TECHNICAL_REFERENCE.md** → Troubleshooting
- Review **mlx_poc/PROGRESS.md** for what worked
- Re-read relevant sections when stuck

### External (Future)
- GitHub Issues
- Documentation
- Community Discord/Slack (TBD)

---

## 🎉 Achievements Unlocked

- ✅ Built working Swift CLI for Granite inference
- ✅ Solved Metal shader compilation mystery
- ✅ Proved full Claude ↔ Granite loop works
- ✅ Eliminated Ollama dependency
- ✅ Reduced maintenance burden by ~50%
- ✅ Created comprehensive documentation
- ✅ **Positioned for production release**

---

*This index created by Claude (Anthropic) and Andrew Carlile*  
*"Documentation is a love letter to your future self"*

---

**Next:** Read [README_MLX.md](README_MLX.md) or dive into [MLX_TECHNICAL_REFERENCE.md](MLX_TECHNICAL_REFERENCE.md)
