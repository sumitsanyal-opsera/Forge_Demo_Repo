import { LightningElement, wire, track } from 'lwc';
import getExecutionHistory from '@salesforce/apex/SmokeTestDashboardController.getExecutionHistory';

// Chart coordinate constants
const C_LEFT   = 47;   // x start of bars (after Y-axis labels)
const C_RIGHT  = 610;  // x end of chart
const C_TOP    = 12;   // y top of bars
const C_BOTTOM = 250;  // y base of bars (x-axis)
const C_WIDTH  = C_RIGHT - C_LEFT;  // usable bar area width
const C_HEIGHT = C_BOTTOM - C_TOP;  // usable bar area height

// Pass rate thresholds
const THRESHOLD_PASS = 80;
const THRESHOLD_WARN = 50;

// Colors
const COLOR_PASS = '#4CAF50';
const COLOR_WARN = '#FF9800';
const COLOR_FAIL = '#F44336';

export default class TrendChart extends LightningElement {
    _rawHistory   = undefined;
    _filtered     = null;
    loadError     = undefined;
    skippedCount  = 0;

    @track _tableVisible = false;
    @track tooltip = { visible: false };

    // =========================================================================
    // Wire
    // =========================================================================

    @wire(getExecutionHistory)
    wiredHistory(result) {
        const { data, error } = result;
        if (data !== undefined) {
            this._rawHistory = data;
            this.loadError   = undefined;
            this._processData(data);
        } else if (error) {
            this.loadError   = error;
            this._rawHistory = undefined;
            this._filtered   = null;
        }
    }

    _processData(records) {
        if (!records || records.length === 0) {
            this._filtered  = [];
            this.skippedCount = 0;
            return;
        }
        // Query returns DESC order; reverse so oldest is left, newest is right
        const all = [...records].reverse();
        const valid   = all.filter(r => r.TotalScenarios__c != null && r.TotalScenarios__c > 0);
        this.skippedCount = all.length - valid.length;
        this._filtered = valid;
    }

    // =========================================================================
    // Visibility guards
    // =========================================================================

    get isLoading() {
        return this._rawHistory === undefined && !this.loadError;
    }

    get hasError() {
        return !!this.loadError;
    }

    get isEmpty() {
        return !this.isLoading && !this.hasError && this._filtered !== null && this._filtered.length === 0;
    }

    get hasData() {
        return !!(this._filtered && this._filtered.length > 0);
    }

    get hasIncompleteData() {
        return this.skippedCount > 0;
    }

    // =========================================================================
    // Table toggle
    // =========================================================================

    get isTableVisible() {
        return this._tableVisible;
    }

    get tableClass() {
        return this._tableVisible
            ? 'trend-table-wrapper slds-m-top_small'
            : 'slds-assistive-text trend-table-wrapper';
    }

    get tableToggleLabel() {
        return this._tableVisible ? 'Hide Data Table' : 'Show Data Table';
    }

    toggleTable() {
        this._tableVisible = !this._tableVisible;
    }

    // =========================================================================
    // SVG: Y-axis gridlines
    // =========================================================================

    get yGridlines() {
        return [0, 25, 50, 75, 100].map(pct => {
            const y = Math.round(C_BOTTOM - (pct / 100) * C_HEIGHT);
            return {
                pct,
                y,
                labelY: y + 3,
                label: `${pct}%`
            };
        });
    }

    // =========================================================================
    // SVG: Bars
    // =========================================================================

    get bars() {
        const data = this._filtered;
        if (!data || data.length === 0) return [];

        const n          = data.length;
        const slotW      = C_WIDTH / n;
        const gap        = Math.min(2, slotW * 0.12);
        const bW         = Math.max(1, Math.floor(slotW - gap));

        return data.map((exec, i) => {
            const total   = exec.TotalScenarios__c  || 0;
            const passed  = exec.PassedScenarios__c || 0;
            const failed  = exec.FailedScenarios__c || 0;
            const passRate = total > 0 ? (passed / total) * 100 : 0;
            const bH      = Math.max(1, Math.round((passRate / 100) * C_HEIGHT));
            const x       = Math.round(C_LEFT + i * slotW + gap / 2);
            const y       = C_BOTTOM - bH;

            const color       = passRate >= THRESHOLD_PASS ? COLOR_PASS
                              : passRate >= THRESHOLD_WARN ? COLOR_WARN
                              : COLOR_FAIL;
            const patternId   = passRate >= THRESHOLD_PASS ? null
                              : passRate >= THRESHOLD_WARN ? 'pattern-warning'
                              : 'pattern-error';

            const dateLabel   = exec.CreatedDate
                ? new Date(exec.CreatedDate).toLocaleDateString('default', { month: 'short', day: 'numeric' })
                : '';
            const dateDisplay = exec.CreatedDate
                ? new Date(exec.CreatedDate).toLocaleDateString('default', { year: 'numeric', month: 'short', day: 'numeric' })
                : 'Unknown';

            return {
                key:          exec.Id || String(i),
                index:        i,
                x,
                y,
                width:        bW,
                height:       bH,
                barStyle:     `fill: ${color};`,
                hasPattern:   !!patternId,
                patternStyle: patternId ? `fill: url(#${patternId}); opacity: 0.4;` : '',
                passRate:     Math.round(passRate),
                createdDate:  exec.CreatedDate,
                tooltipText:  `${Math.round(passRate)}% — ${dateDisplay} (${passed}/${total})`,
                dateLabel,
                midX:         Math.round(x + bW / 2),
                passed,
                failed,
                total
            };
        });
    }

    // =========================================================================
    // SVG: X-axis labels (thinned to avoid overlap)
    // =========================================================================

    get xLabels() {
        const allBars = this.bars;
        if (!allBars || allBars.length === 0) return [];

        const n    = allBars.length;
        const step = n <= 10 ? 1
                   : n <= 20 ? 2
                   : n <= 30 ? 5
                   : 5;

        return allBars
            .filter((_, i) => i % step === 0 || i === n - 1)
            .map(bar => ({
                key:  bar.key,
                x:    bar.midX,
                text: bar.dateLabel
            }));
    }

    // =========================================================================
    // Data table rows
    // =========================================================================

    get tableRows() {
        return (this._filtered || []).map(exec => {
            const total   = exec.TotalScenarios__c  || 0;
            const passed  = exec.PassedScenarios__c || 0;
            const failed  = exec.FailedScenarios__c || 0;
            const timedOut = Math.max(0, total - passed - failed);
            const rate    = total > 0 ? Math.round((passed / total) * 100) : 0;
            return {
                id:           exec.Id,
                createdDate:  exec.CreatedDate,
                passRateLabel: `${rate}%`,
                passed,
                failed,
                timedOut,
                total
            };
        });
    }

    // =========================================================================
    // Tooltip
    // =========================================================================

    handleBarHover(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const bar = this.bars[idx];
        if (!bar) return;
        const rect = event.currentTarget.closest('.chart-wrapper').getBoundingClientRect();
        const barRect = event.currentTarget.getBoundingClientRect();
        const left = barRect.left - rect.left + barRect.width / 2;
        const top  = barRect.top  - rect.top  - 70;
        this.tooltip = {
            visible:  true,
            passRate: bar.passRate,
            date:     bar.dateLabel,
            counts:   `${bar.passed}/${bar.total} passed`,
            style:    `left:${Math.round(left)}px;top:${Math.round(Math.max(4, top))}px;`
        };
    }

    handleChartLeave() {
        this.tooltip = { visible: false };
    }

    // =========================================================================
    // Error retry
    // =========================================================================

    handleRetry() {
        this.loadError   = undefined;
        this._rawHistory = undefined;
        this._filtered   = null;
        getExecutionHistory()
            .then(data  => { this._rawHistory = data; this._processData(data); })
            .catch(err  => { this.loadError = err; });
    }
}
