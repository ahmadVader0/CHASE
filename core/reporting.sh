#!/usr/bin/env bash
# =============================================================================
#  core/reporting.sh — JSON builder, HTML builder, delta diff, summary
#  Sourced by chase.sh after all modules have run.
# =============================================================================

# --- Suppress findings listed in suppressions.list --------------------------
apply_suppressions() {
    local suppression_file="$1"
    [[ ! -f "$suppression_file" ]] && return 0

    while IFS= read -r pattern; do
        # Skip blank lines and comments
        [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue

        # Use "|" as sed delimiter to prevent path slash bugs
        sed -i "\|${pattern}|d" "$TMP_FINDINGS_FILE" 2>/dev/null || true
    done < "$suppression_file"
}

# --- JSON report -------------------------------------------------------------
generate_json_report() {
    local out_file="$1"
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    cat > "$out_file" <<EOF
{
  "scan_metadata": {
    "timestamp": "${timestamp}",
    "hostname": "$(hostname)",
    "kernel": "$(uname -r)",
    "chase_version": "${CHASE_VERSION}"
  },
  "findings": [
EOF

    local first=1
    while IFS=$'\t' read -r severity domain title remediation benchmark; do
        [[ "$first" -eq 1 ]] || printf ',\n' >> "$out_file"
        first=0

        # Escape all JSON fields safely
        title="$(json_escape "$title")"
        remediation="$(json_escape "$remediation")"
        domain="$(json_escape "$domain")"
        benchmark="$(json_escape "$benchmark")"
        severity="$(json_escape "$severity")"

        cat >> "$out_file" <<EOF
    {
      "severity": "${severity}",
      "domain": "${domain}",
      "title": "${title}",
      "remediation": "${remediation}",
      "benchmark": "${benchmark}"
    }
EOF
    done < "$TMP_FINDINGS_FILE"

    printf '\n  ]\n}\n' >> "$out_file"
    chmod 600 "$out_file"
    log_info "JSON report saved  : ${out_file}"
}

# --- HTML report -------------------------------------------------------------
generate_html_report() {
    local out_file="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    local n_crit n_high n_med n_low
    n_crit="$(grep -c '^CRITICAL' "$TMP_FINDINGS_FILE" 2>/dev/null || echo 0)"
    n_high="$(grep -c '^HIGH'     "$TMP_FINDINGS_FILE" 2>/dev/null || echo 0)"
    n_med="$( grep -c '^MEDIUM'   "$TMP_FINDINGS_FILE" 2>/dev/null || echo 0)"
    n_low="$( grep -c '^LOW'      "$TMP_FINDINGS_FILE" 2>/dev/null || echo 0)"

    # Hardening Score calculation
    local score=100
    local crit_deduction=$(( n_crit * 15 ))
    local high_deduction=$(( n_high * 10 ))
    local med_deduction=$(( n_med * 5 ))
    local low_deduction=$(( n_low * 2 ))
    local total_deduction=$(( crit_deduction + high_deduction + med_deduction + low_deduction ))
    score=$(( score - total_deduction ))
    if (( score < 10 )); then
        score=10
    fi

    # SVG Dash Offset (radius = 70, circumference = 2 * pi * 70 approx 439.82)
    local circumference=440
    local offset=$(( circumference - (circumference * score / 100) ))

    # Determine color of gauge based on score
    local gauge_color="var(--color-pass)"
    if (( score < 60 )); then
        gauge_color="var(--color-crit)"
    elif (( score < 85 )); then
        gauge_color="var(--color-med)"
    fi

    # Load CSS from templates/report.css
    local css_file="${CHASE_DIR}/templates/report.css"
    local css_content
    if [[ -r "$css_file" ]]; then
        css_content="$(cat "$css_file")"
    else
        log_warn "templates/report.css not found — using minimal inline fallback"
        css_content="body{background:#050811;color:#f8fafc;font-family:sans-serif;padding:2rem}"
    fi

    # Write HTML Header
    {
        printf '<!DOCTYPE html>\n<html lang="en">\n<head>\n'
        printf '  <meta charset="UTF-8">\n'
        printf '  <meta name="viewport" content="width=device-width, initial-scale=1">\n'
        printf '  <title>CHASE Security Audit Report</title>\n'
        printf '  <style>\n%s\n  </style>\n' "$css_content"
        printf '</head>\n<body>\n'
        printf '<div class="container">\n'
        printf '  <header>\n'
        printf '    <h1>🛡️ CHASE Security Audit</h1>\n'
        printf '    <h2>Configuration &amp; Host Audit Security Evaluator</h2>\n'
        printf '    <div class="meta-grid">\n'
        printf '      <div class="meta-item">Host: <strong>%s</strong></div>\n' "$(hostname)"
        printf '      <div class="meta-item">Kernel: <strong>%s</strong></div>\n' "$(uname -r)"
        printf '      <div class="meta-item">Scan Time: <strong>%s</strong></div>\n' "$timestamp"
        printf '      <div class="meta-item">CHASE Version: <strong>v%s</strong></div>\n' "$CHASE_VERSION"
        printf '    </div>\n'
        printf '  </header>\n\n'
    } > "$out_file"

    # Start Layout Grid
    cat >> "$out_file" <<EOF
  <div class="dashboard-layout">
    <!-- Sidebar Panel (Gauge & Download Script) -->
    <aside class="sidebar">
      <div class="panel-card">
        <h3>Hardening Posture</h3>
        <div class="gauge-container">
          <svg class="gauge-svg" viewBox="0 0 160 160">
            <!-- Background circle -->
            <circle class="gauge-bg" cx="80" cy="80" r="70" />
            <!-- Fill circle -->
            <circle class="gauge-fill" cx="80" cy="80" r="70" 
                    style="stroke: ${gauge_color}; stroke-dasharray: ${circumference}; stroke-dashoffset: ${offset};" />
            <!-- Gauge values -->
            <text class="gauge-text-val" x="80" y="85" font-size="28">${score}%</text>
            <text class="gauge-text-lbl" x="80" y="110">Score</text>
          </svg>
        </div>
      </div>

      <div class="panel-card script-card">
        <h3>Remediation Center</h3>
        <p>Generate and download a customized, executable bash script containing all non-suppressed remediation commands found in this audit.</p>
        <button class="btn-download-script" onclick="downloadRemediationScript()">Download Remediation Script</button>
      </div>
    </aside>

    <!-- Main Content Area -->
    <main class="main-panel">
      <!-- Executive Summary -->
      <section class="summary-container">
        <div class="stats-grid">
          <div class="stat-card crit" data-severity="critical">
            <div class="stat-num">${n_crit}</div>
            <div class="stat-label">Critical</div>
          </div>
          <div class="stat-card high" data-severity="high">
            <div class="stat-num">${n_high}</div>
            <div class="stat-label">High</div>
          </div>
          <div class="stat-card med" data-severity="medium">
            <div class="stat-num">${n_med}</div>
            <div class="stat-label">Medium</div>
          </div>
          <div class="stat-card low" data-severity="low">
            <div class="stat-num">${n_low}</div>
            <div class="stat-label">Low</div>
          </div>
        </div>
      </section>

      <!-- Toolbar / Search and Filters -->
      <div class="toolbar">
        <div class="search-box">
          <input type="text" id="search-input" placeholder="Search findings by domain, title, or reference..." />
        </div>
        <div class="filter-group">
          <button class="btn-filter active" data-filter="all">All</button>
          <button class="btn-filter" data-filter="CRITICAL">Critical</button>
          <button class="btn-filter" data-filter="HIGH">High</button>
          <button class="btn-filter" data-filter="MEDIUM">Medium</button>
          <button class="btn-filter" data-filter="LOW">Low</button>
        </div>
      </div>

      <!-- Findings List -->
      <section class="findings-container">
        <div class="findings-list" id="findings-list">
EOF

    # Write Findings Cards
    local card_id=0
    while IFS=$'\t' read -r severity domain title remediation benchmark; do
        card_id=$((card_id + 1))
        # Escape fields safely for HTML
        title="$(html_escape "$title")"
        domain="$(html_escape "$domain")"
        remediation="$(html_escape "$remediation")"
        benchmark="$(html_escape "$benchmark")"

        cat >> "$out_file" <<EOF
          <div class="card ${severity}" data-severity="${severity}" data-domain="${domain}">
            <div class="card-header" onclick="toggleCard(this)">
              <div class="card-header-main">
                <span class="badge ${severity}">${severity}</span>
                <span class="domain-tag">${domain}</span>
                <span class="card-title">${title}</span>
              </div>
              <span class="card-chevron">❯</span>
            </div>
            <div class="card-details">
              <div class="detail-label">Remediation Script</div>
              <div class="code-container">
                <code id="code-${card_id}">${remediation}</code>
                <button class="btn-copy" onclick="copyCode('code-${card_id}', this)">Copy Fix</button>
              </div>
              <div class="detail-label">Benchmark Reference</div>
              <div class="bench-info">${benchmark}</div>
            </div>
          </div>
EOF
    done < "$TMP_FINDINGS_FILE"

    # Empty State for searches
    cat >> "$out_file" <<EOF
          <div class="empty-state" id="empty-state">
            <p>No matching findings detected.</p>
            <span>Try adjusting your search query or severity filters</span>
          </div>
EOF

    # Close layout, footer, and inject JavaScript
    cat >> "$out_file" <<'HTML'
        </div>
      </section>
    </main>
  </div> <!-- Close layout grid -->

  <footer>Generated by CHASE — pure Bash security framework.</footer>
</div>

<script>
  // Toggle collapsible card
  function toggleCard(headerElement) {
    const card = headerElement.parentElement;
    card.classList.toggle('open');
  }

  // Copy remediation script to clipboard
  function copyCode(codeId, button) {
    const codeText = document.getElementById(codeId).innerText;
    navigator.clipboard.writeText(codeText).then(() => {
      button.innerText = 'Copied!';
      button.classList.add('copied');
      setTimeout(() => {
        button.innerText = 'Copy Fix';
        button.classList.remove('copied');
      }, 2000);
    }).catch(err => {
      console.error('Failed to copy text: ', err);
    });
  }

  // Download all remediation commands as a single script on-the-fly
  function downloadRemediationScript() {
    let scriptContent = "#!/usr/bin/env bash\n";
    scriptContent += "# =============================================================================\n";
    scriptContent += "#  CHASE Generated Remediation Script\n";
    scriptContent += "#  Generated on: " + new Date().toLocaleString() + "\n";
    scriptContent += "#  Target Host: " + window.location.hostname + "\n";
    scriptContent += "# =============================================================================\n\n";
    scriptContent += "if [ \"$EUID\" -ne 0 ]; then\n  echo \"Please run as root.\" >&2\n  exit 1\nfi\n\n";

    const codes = document.querySelectorAll(".code-container code");
    let count = 0;
    codes.forEach((codeEl) => {
      const card = codeEl.closest(".card");
      const title = card.querySelector(".card-title").innerText;
      const severity = card.querySelector(".badge").innerText;
      const domain = card.querySelector(".domain-tag").innerText;
      const command = codeEl.innerText.trim();

      if (command && command !== "N/A" && command !== "n/a") {
        count++;
        scriptContent += "# Finding #" + count + " [" + severity + "] " + domain + ": " + title + "\n";
        scriptContent += "echo \"Applying fix for: " + title.replace(/"/g, '\\"') + "...\"\n";
        scriptContent += command + "\n\n";
      }
    });

    if (count === 0) {
      alert("No remediation commands to download.");
      return;
    }

    const blob = new Blob([scriptContent], { type: "text/plain;charset=utf-8" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = "chase_remediations.sh";
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  }

  // Interactive filtering & search
  const searchInput = document.getElementById('search-input');
  const filterButtons = document.querySelectorAll('.btn-filter');
  const cards = document.querySelectorAll('.card');
  const emptyState = document.getElementById('empty-state');

  let activeFilter = 'all';
  let searchQuery = '';

  function applyFilters() {
    let visibleCount = 0;
    cards.forEach(card => {
      const severity = card.getAttribute('data-severity');
      const textContent = card.innerText.toLowerCase();

      const matchesFilter = (activeFilter === 'all' || severity === activeFilter);
      const matchesSearch = textContent.includes(searchQuery);

      if (matchesFilter && matchesSearch) {
        card.style.display = 'block';
        visibleCount++;
      } else {
        card.style.display = 'none';
      }
    });

    if (visibleCount === 0 && cards.length > 0) {
      emptyState.style.display = 'block';
    } else {
      emptyState.style.display = 'none';
    }
  }

  // Search input listener
  searchInput.addEventListener('input', (e) => {
    searchQuery = e.target.value.toLowerCase();
    applyFilters();
  });

  // Filter button listener
  filterButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      filterButtons.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      activeFilter = btn.getAttribute('data-filter');
      applyFilters();
    });
  });
</script>
</body>
</html>
HTML

    chmod 600 "$out_file"
    log_info "HTML report saved : ${out_file}"
}

# --- Delta report — new vs resolved since last scan -------------------------
run_delta_report() {
    local baseline_dir="${REPORT_DIR}"
    local baseline="${baseline_dir}/last_baseline.tsv"
    local current="$TMP_FINDINGS_FILE"

    mkdir -p "$baseline_dir"

    if [[ ! -f "$baseline" ]]; then
        log_info "First scan baseline generated."
        cp "$current" "$baseline"
        return 0
    fi

    local new_findings resolved_findings
    new_findings="$(comm -23 <(sort "$current") <(sort "$baseline") 2>/dev/null || true)"
    resolved_findings="$(comm -13 <(sort "$current") <(sort "$baseline") 2>/dev/null || true)"

    echo ""
    if [[ -n "$new_findings" ]]; then
        log_high "⚠ NEW findings since last scan:"
        while IFS=$'\t' read -r sev dom title _ _; do
            printf "  ${CRIMSON}+${RESET} [%s] [%s] %s\n" "$sev" "$dom" "$title"
        done <<< "$new_findings"
    else
        log_ok "No new findings since last scan."
    fi

    if [[ -n "$resolved_findings" ]]; then
        echo ""
        log_ok "✓ RESOLVED since last scan:"
        while IFS=$'\t' read -r sev dom title _ _; do
            printf "  ${GREEN}─${RESET} [%s] [%s] %s\n" "$sev" "$dom" "$title"
        done <<< "$resolved_findings"
    fi

    cp "$current" "$baseline"
}

# --- Terminal summary --------------------------------------------------------
print_summary() {
    local report_base="$1"

    local n_crit n_high n_med n_low total
    n_crit="$(grep -c '^CRITICAL' "$TMP_FINDINGS_FILE" 2>/dev/null || echo 0)"
    n_high="$(grep -c '^HIGH'     "$TMP_FINDINGS_FILE" 2>/dev/null || echo 0)"
    n_med="$( grep -c '^MEDIUM'   "$TMP_FINDINGS_FILE" 2>/dev/null || echo 0)"
    n_low="$( grep -c '^LOW'      "$TMP_FINDINGS_FILE" 2>/dev/null || echo 0)"
    total=$(( n_crit + n_high + n_med + n_low ))

    echo ""
    echo "${CHARCOAL}===========================================================================${RESET}"
    printf  "${BOLD}%*s📊  CHASE AUDIT REPORT SUMMARY%*s${RESET}\n" 17 '' 17 ''
    echo "${CHARCOAL}===========================================================================${RESET}"
    printf "  ${RED}${BOLD}[!] CRITICAL${RESET} : %d\n"  "$n_crit"
    printf "  ${ORANGE}[-] HIGH${RESET}     : %d\n"  "$n_high"
    printf "  ${YELLOW}[i] MEDIUM${RESET}   : %d\n"  "$n_med"
    printf "  ${ASH}[v] LOW${RESET}      : %d\n"  "$n_low"
    printf "       ${CHARCOAL}─────────────────${RESET}\n"
    printf "       Total        : %d\n"  "$total"
    echo "${CHARCOAL}===========================================================================${RESET}"
    printf "  HTML Report : %s.html\n" "$report_base"
    printf "  JSON Report : %s.json\n" "$report_base"
    echo "${CHARCOAL}===========================================================================${RESET}"
    echo ""
}
