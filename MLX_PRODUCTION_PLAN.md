# Cloud2Ground MLX Production Plan

**Status:** POC Complete ✅ — Ready for Production Implementation  
**Timeline:** 4-8 weeks to production release  
**Goal:** Replace Ollama with MLX-Swift in production Cloud2Ground system

---

## Vision

A streamlined, Mac-native Cloud2Ground AI assistant powered entirely by:
- **Claude Desktop** (cloud intelligence)
- **MLX-Swift** (local Granite inference)
- **Zero external dependencies** (no Ollama, no Python, no cross-platform complexity)

**Maintenance reduced by ~50%**. Updates only to:
1. Claude delegation skill (as needed)
2. Granite models (when IBM releases new versions)

---

## Phases

### Phase 1: Internal Testing & Feature Parity (Week 1-2)

**Goal:** Make MLX watcher feature-complete with Ollama watcher

#### Tasks

**1.1 Port Missing Features from Ollama Watcher**

- [ ] **Heartbeat / status.json writer**
  - Write `status.json` every 5 seconds
  - Include: status, model, last_heartbeat, version
  - Format:
    ```json
    {
      "status": "ready",
      "model": "granite-3.3-2b-instruct-8bit",
      "last_heartbeat": 1784415994,
      "version": "mlx-1.0",
      "backend": "mlx-swift"
    }
    ```

- [ ] **Token counting & savings ledger**
  - Count input/output tokens using tokenizer
  - Estimate Claude API cost saved
  - Log to `~/claude_bridge/savings.json`
  - Format:
    ```json
    {
      "total_requests": 142,
      "total_input_tokens": 12450,
      "total_output_tokens": 38920,
      "estimated_cost_saved_usd": 1.24,
      "last_updated": 1784415994
    }
    ```

- [ ] **Markdown fence stripping**
  - Strip ```language fences from responses
  - Config option to enable/disable
  - Current Ollama watcher does this — port logic

- [ ] **Stale lock garbage collection**
  - On startup, check `processing.lock`
  - If PID doesn't exist, remove lock
  - Prevents stuck watchers after crashes

- [ ] **Configurable temperature**
  - Default: 0.2 (match production Ollama setting)
  - Override via env: `C2G_MLX_TEMPERATURE=0.2`
  - Use MLX `GenerateParameters`:
    ```swift
    let params = GenerateParameters(
        temperature: temperature,
        topP: 0.9,
        maxTokens: 4096
    )
    ```

**1.2 Test with Real Workflows**

- [ ] Use MLX watcher for daily work (eat our own dog food)
- [ ] Test diverse prompts:
  - Code generation
  - Shell commands
  - Explanations
  - Debugging
- [ ] Monitor for edge cases, crashes, hangs
- [ ] Document any issues

**1.3 Model Quality Comparison**

- [ ] Test 2B vs 8B models side-by-side
- [ ] Quality metrics:
  - Code correctness
  - Explanation clarity
  - Command safety
- [ ] Decision: Which model for production?
  - Recommendation: **8B for production** (better quality, worth the size)
  - Keep 2B as "fast mode" option

**Deliverables:**
- Feature-complete `watch_mlx.sh` v2
- Internal test report
- Model recommendation

**Success Criteria:**
- All Ollama watcher features ported
- No showstopper bugs in daily use
- Performance acceptable (response time < 10s for most queries)

---

### Phase 2: Packaging & Installation (Week 3-4)

**Goal:** Make it easy to install and run

#### Tasks

**2.1 Create Installer Script**

- [ ] **install_cloud2ground_mlx.sh**
  - Downloads latest binary + metallib
  - Installs to `/usr/local/bin/`
  - Creates `~/Library/Application Support/claude_bridge/`
  - Copies `watch_mlx.sh` to app support dir
  - Sets up launchd plist (optional)
  - Pre-downloads 8B model (with progress bar)

- [ ] **Uninstaller**
  - Removes binaries
  - Stops launchd service
  - Optionally removes model cache (~8 GB)

**2.2 Auto-Start with launchd**

- [ ] Create `com.cloud2ground.mlx-watcher.plist`
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ...>
  <plist version="1.0">
  <dict>
      <key>Label</key>
      <string>com.cloud2ground.mlx-watcher</string>
      <key>ProgramArguments</key>
      <array>
          <string>/usr/local/bin/watch_mlx.sh</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <true/>
      <key>StandardOutPath</key>
      <string>/tmp/c2g-mlx-watcher.log</string>
      <key>StandardErrorPath</key>
      <string>/tmp/c2g-mlx-watcher.err</string>
  </dict>
  </plist>
  ```

- [ ] Install with:
  ```bash
  cp com.cloud2ground.mlx-watcher.plist ~/Library/LaunchAgents/
  launchctl load ~/Library/LaunchAgents/com.cloud2ground.mlx-watcher.plist
  ```

**2.3 User Documentation**

- [ ] **README.md** (user-facing)
  - What is Cloud2Ground?
  - Requirements
  - Installation steps
  - How to use
  - Troubleshooting

- [ ] **UPGRADE_FROM_OLLAMA.md**
  - For existing Ollama users
  - Migration steps
  - How to uninstall Ollama
  - Verification steps

- [ ] **FAQ.md**
  - Common questions
  - Performance expectations
  - Model selection guide
  - Privacy/security notes

**2.4 DMG Creation (Optional)**

- [ ] Build proper Mac app bundle
- [ ] Code sign with Apple Developer ID
- [ ] Create DMG with drag-to-install
- [ ] Notarize for Gatekeeper

(This is nice-to-have, not required for initial release)

**Deliverables:**
- `install_cloud2ground_mlx.sh`
- `uninstall_cloud2ground_mlx.sh`
- launchd plist
- User documentation

**Success Criteria:**
- Fresh Mac can install in < 5 minutes
- Watcher auto-starts on login
- User docs clear and complete

---

### Phase 3: Skill Integration (Week 5)

**Goal:** Update delegation skill to work with MLX watcher

#### Tasks

**3.1 Update Delegation Skill**

Current skill checks for `start_local_ai.sh` process. Update to:

- [ ] Check for `watch_mlx.sh` OR `start_local_ai.sh`
- [ ] Check `status.json` includes `"backend": "mlx-swift"`
- [ ] Update skill metadata to indicate MLX support
- [ ] Add fallback: if MLX not available, suggest installation

**3.2 Test Skill with MLX**

- [ ] Load updated skill in Claude Desktop
- [ ] Test delegation triggers
- [ ] Test response handling
- [ ] Test error cases (watcher down, model failed, etc.)

**3.3 Backward Compatibility**

- [ ] Ensure skill still works with Ollama (for users not yet migrated)
- [ ] Provide clear messaging about which backend is active
- [ ] Document migration path in skill

**Deliverables:**
- Updated `cloud2ground_local_ai.txt` skill
- Test results

**Success Criteria:**
- Skill correctly detects and uses MLX watcher
- Seamless user experience (no visible change from user perspective)
- Backward compatible with Ollama

---

### Phase 4: Alpha Release (Week 6)

**Goal:** Limited release to testers

#### Tasks

**4.1 Prepare Release Artifacts**

- [ ] Build final release binary
- [ ] Package installer
- [ ] Prepare docs
- [ ] Create GitHub release (or distribution method)

**4.2 Alpha Testing**

- [ ] 5-10 alpha testers
- [ ] Install instructions
- [ ] Feedback form / issue tracker
- [ ] Weekly check-ins

**4.3 Monitor & Fix**

- [ ] Collect crash logs
- [ ] Monitor feedback
- [ ] Fix critical bugs
- [ ] Update docs based on confusion points

**Deliverables:**
- Alpha release package
- Tester feedback report
- Bug fix releases as needed

**Success Criteria:**
- Alpha testers can install successfully
- No critical bugs
- Positive feedback on performance

---

### Phase 5: Production Release (Week 7-8)

**Goal:** Public release, Ollama deprecation

#### Tasks

**5.1 Final Polish**

- [ ] Address all alpha feedback
- [ ] Performance optimization if needed
- [ ] Final doc review
- [ ] Release notes

**5.2 Public Release**

- [ ] Publish installer
- [ ] Update main Cloud2Ground README to MLX-first
- [ ] Deprecate Ollama instructions (move to legacy doc)
- [ ] Announce release

**5.3 Migration Support**

- [ ] Monitor issues
- [ ] Help users migrate from Ollama
- [ ] Create migration guide video (optional)
- [ ] Answer questions

**Deliverables:**
- Production release v1.0
- Release announcement
- Migration guide

**Success Criteria:**
- Smooth rollout
- No critical issues
- Positive user reception

---

## Post-Release: Ongoing Optimization

### Short Term (Month 2-3)

- **Streaming responses**
  - Update bridge protocol for partial responses
  - Update skill to handle streaming
  - Better UX for long generations

- **Multi-model support**
  - Easy model switching
  - Model selection in skill
  - "Fast mode" (2B) vs "Quality mode" (8B)

- **Performance monitoring**
  - Telemetry (opt-in)
  - Response time tracking
  - Quality feedback

### Medium Term (Month 4-6)

- **Fine-tuning experiments**
  - Collect C2G-specific training data
  - Fine-tune Granite for shell commands
  - Fine-tune for code explanation
  - A/B test quality improvements

- **Advanced sampling**
  - Temperature scheduling
  - Dynamic max tokens based on query type
  - Custom sampling for different task types

- **Model caching optimization**
  - Keep model loaded in memory between requests
  - Reduce cold-start latency
  - Balance memory vs. responsiveness

### Long Term (Month 6+)

- **Multi-modal support**
  - When Granite adds vision capabilities
  - Screenshot analysis
  - Diagram explanation

- **Specialized models**
  - Code-specific fine-tune
  - Shell-specific fine-tune
  - Documentation-specific fine-tune
  - Load different models for different task types

- **Community contributions**
  - Open-source the MLX integration
  - Accept community model recommendations
  - Support community fine-tunes

---

## Resource Requirements

### Development Time

| Phase | Estimated Time | Confidence |
|-------|---------------|------------|
| Phase 1 | 10-15 hours | High |
| Phase 2 | 8-12 hours | High |
| Phase 3 | 4-6 hours | High |
| Phase 4 | 10-15 hours (includes testing) | Medium |
| Phase 5 | 8-12 hours (includes support) | Medium |
| **Total** | **40-60 hours** | **~1-2 months calendar time** |

### Hardware Requirements

**Development:**
- Apple Silicon Mac (M1/M2/M3/M4)
- 16 GB RAM minimum (for 8B model)
- 50 GB free disk space (for builds + models)

**Testing:**
- Multiple Mac configurations if possible
- Various macOS versions (14.0+)

**Production (user machines):**
- Apple Silicon Mac
- 8 GB RAM minimum (2B model)
- 16 GB RAM recommended (8B model)
- ~10 GB disk space

### Cost

- $0 development cost (using existing hardware)
- $0 runtime cost (no API fees, no cloud)
- $0 licensing (open source dependencies)
- Optional: Apple Developer Program ($99/year for code signing)

---

## Risk Management

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Metal shader issues on different GPUs | Low | High | Test on M1/M2/M3 variants |
| Model quality insufficient | Medium | High | Test 8B model, collect feedback early |
| Memory issues on 8GB Macs | Medium | Medium | Support 2B model as alternative |
| MLX API breaking changes | Low | Medium | Pin dependency versions |
| Model downloads fail | Medium | Low | Retry logic, mirrors |

### User Adoption Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Users prefer Ollama | Low | Medium | Show performance benefits, ease of use |
| Installation too complex | Medium | High | Make installer bulletproof |
| Model quality complaints | Medium | High | Set expectations, offer 8B |
| Support burden too high | Low | Medium | Good docs, FAQ, troubleshooting guide |

### Organizational Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Lose interest mid-project | Low | High | Phased approach, early wins |
| IBM stops Granite development | Very Low | High | Models are open, can fork |
| MLX-Swift development stalls | Very Low | Medium | Apple-backed, active community |

---

## Success Metrics

### Phase 1 (Internal Testing)
- [ ] 0 critical bugs in 2 weeks of daily use
- [ ] Response quality "as good or better" than Ollama
- [ ] All features ported

### Phase 2 (Packaging)
- [ ] Install completes in < 5 minutes
- [ ] 0 manual configuration needed
- [ ] Watcher auto-starts reliably

### Phase 3 (Skill Integration)
- [ ] Delegation works 100% of time
- [ ] No false negatives (should delegate but doesn't)
- [ ] No false positives (shouldn't delegate but does)

### Phase 4 (Alpha)
- [ ] 5+ alpha testers successfully installed
- [ ] > 80% positive feedback
- [ ] < 3 critical bugs reported

### Phase 5 (Production)
- [ ] Public release published
- [ ] > 90% of users migrate from Ollama
- [ ] < 5% support burden vs development time

### Long-term (6 months)
- [ ] Active daily users > 10
- [ ] Maintenance time < 2 hours/month
- [ ] User satisfaction > 85%

---

## Decision Points

### After Phase 1: 2B vs 8B Model

**Criteria:**
- Quality (code correctness, explanations)
- Speed (acceptable wait time)
- Memory (8GB Macs must work)

**Decision:**
- If 8B significantly better AND 8GB Macs can run it → 8B default
- If 8B marginal improvement OR 8GB Macs struggle → 2B default with 8B as option
- If 2B insufficient quality → require 16GB RAM, 8B only

### After Phase 4: Ready for Production?

**Go criteria:**
- No critical bugs
- Positive alpha feedback (> 80%)
- Installation success rate > 95%
- Documentation complete

**No-go scenarios:**
- Critical unsolved bug
- Poor model quality
- Installation too complex
- Negative alpha feedback

### After Phase 5: Continue Development?

**Continue if:**
- Active user base (> 5 regular users)
- Positive feedback
- Low maintenance burden
- Value clear (vs. Ollama or cloud-only)

**Pause/pivot if:**
- No users after 3 months
- Negative feedback (prefer Ollama)
- High maintenance burden
- IBM discontinues Granite

---

## Communication Plan

### Internal (You)

- Track progress in this document
- Weekly self-check-ins
- Update PROGRESS.md as milestones hit

### Alpha Testers

- Onboarding email with clear instructions
- Weekly update emails
- Feedback form (Google Forms or similar)
- Slack/Discord channel for real-time support (optional)

### Public (After Phase 5)

- Release announcement (blog post, Twitter, etc.)
- Updated README on GitHub
- Migration guide for Ollama users
- Changelog for updates

---

## Rollback Plan

If MLX migration fails or proves inferior:

1. **Keep Ollama instructions available** (in LEGACY.md)
2. **Skill supports both backends** (already planned)
3. **Users can easily switch back**:
   ```bash
   launchctl unload ~/Library/LaunchAgents/com.cloud2ground.mlx-watcher.plist
   # Restart Ollama watcher
   ```
4. **Document lessons learned**
5. **No harm done** (POC in separate directory, production untouched)

---

## Appendix: Quick Reference

### Commands

```bash
# Build
cd c2g-mlx && swift build -c release && cd .. && ./BUILD_METALLIB.sh

# Run watcher
./watch_mlx.sh

# Test
./bridge_test.sh "test prompt"

# Switch model
export C2G_MLX_MODEL=mlx-community/granite-3.3-8b-instruct-8bit

# Check status
cat ~/claude_bridge/_bridge/status.json

# View logs
tail -f ~/claude_bridge/_bridge/mlx.log

# Monitor watcher
ps aux | grep watch_mlx
```

### File Locations

- Binary: `c2g-mlx/.build/arm64-apple-macosx/release/c2g-mlx`
- Metal lib: `c2g-mlx/.build/arm64-apple-macosx/release/mlx.metallib`
- Watcher: `watch_mlx.sh`
- Bridge: `~/claude_bridge/_bridge/`
- Models: `~/.cache/huggingface/hub/`
- Logs: `~/claude_bridge/_bridge/mlx.log`

### Support Resources

- MLX-Swift docs: https://swiftpackageindex.com/ml-explore/mlx-swift/main/documentation/mlx
- MLX-Swift-LM: https://github.com/ml-explore/mlx-swift-lm
- Granite models: https://huggingface.co/mlx-community?search_models=granite
- This documentation: `MLX_TECHNICAL_REFERENCE.md`

---

*Roadmap version: 1.0*  
*Created: 2026-07-18*  
*Status: Active — POC Complete, Ready for Phase 1*
