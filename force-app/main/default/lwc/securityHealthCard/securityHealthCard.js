import { LightningElement, api, track } from 'lwc';
import getLatestSecurityScore from '@salesforce/apex/SmokeTestSecurityController.getLatestSecurityScore';

const GAUGE_RADIUS = 50;
const GAUGE_CIRCUMFERENCE = 2 * Math.PI * GAUGE_RADIUS;

export default class SecurityHealthCard extends LightningElement {
    /** Passed by parent after permission check. No Apex calls or markup when false. */
    @api isAdmin = false;

    @track _scoreData = undefined;
    @track _loadError = undefined;
    @track _isLoading = false;

    connectedCallback() {
        if (this.isAdmin) {
            this._fetchScore();
        }
    }

    async _fetchScore() {
        this._isLoading = true;
        try {
            this._scoreData = await getLatestSecurityScore();
            this._loadError = undefined;
        } catch (err) {
            this._loadError = err;
            this._scoreData = undefined;
        } finally {
            this._isLoading = false;
        }
    }

    // =========================================================================
    // Visibility guards
    // =========================================================================

    get isLoading() {
        return this._isLoading;
    }

    get hasError() {
        return !this._isLoading && !!this._loadError;
    }

    get hasNoData() {
        return !this._isLoading && !this._loadError && this._scoreData === null;
    }

    get hasData() {
        return !this._isLoading && !this._loadError && this._scoreData != null;
    }

    // =========================================================================
    // Score values
    // =========================================================================

    get postScore() {
        return this._scoreData != null ? this._scoreData.PostDeploymentScore__c : 0;
    }

    get preScore() {
        return this._scoreData != null ? this._scoreData.PreDeploymentScore__c : null;
    }

    get hasPreScore() {
        return this.preScore != null;
    }

    // =========================================================================
    // SVG gauge ring (AC-1)
    // =========================================================================

    /** Returns 'C C' string for stroke-dasharray where C = full circumference. */
    get gaugeDasharray() {
        return `${GAUGE_CIRCUMFERENCE} ${GAUGE_CIRCUMFERENCE}`;
    }

    /** Returns stroke-dashoffset so the foreground arc fills proportionally. */
    get gaugeDashoffset() {
        const score = this.postScore != null ? this.postScore : 0;
        const clamped = Math.max(0, Math.min(100, score));
        return GAUGE_CIRCUMFERENCE * (1 - clamped / 100);
    }

    /** Color class: green ≥ threshold, yellow within 5pts, red below. */
    get gaugeFgClass() {
        const score = this.postScore != null ? this.postScore : 0;
        const threshold = this.threshold != null ? this.threshold : 80;
        if (score >= threshold) {
            return 'gauge-fg gauge-green';
        }
        if (score >= threshold - 5) {
            return 'gauge-fg gauge-yellow';
        }
        return 'gauge-fg gauge-red';
    }

    /** Accessible label read by screen readers (AC-6). */
    get gaugeAriaLabel() {
        return `Security health score: ${this.postScore} out of 100`;
    }

    // =========================================================================
    // Delta (AC-3)
    // =========================================================================

    get delta() {
        return this._scoreData != null ? this._scoreData.ScoreDelta__c : null;
    }

    get hasDelta() {
        return this.delta != null;
    }

    get deltaDisplay() {
        const d = this.delta;
        if (d == null) return 'N/A';
        if (d > 0) return `+${d}`;
        return `${d}`;
    }

    get deltaIcon() {
        const d = this.delta;
        if (d == null || d === 0) return 'utility:dash';
        return d > 0 ? 'utility:arrowup' : 'utility:arrowdown';
    }

    get deltaClass() {
        const d = this.delta;
        if (d == null) return 'slds-dl_horizontal__detail';
        if (d < 0) return 'slds-dl_horizontal__detail delta-negative';
        return 'slds-dl_horizontal__detail delta-positive';
    }

    // =========================================================================
    // Threshold (AC-2)
    // =========================================================================

    get threshold() {
        return this._scoreData != null ? this._scoreData.AbsoluteThreshold__c : 80;
    }

    get thresholdStatusLabel() {
        if (!this._scoreData) return '';
        const status = this._scoreData.ThresholdStatus__c;
        if (status === 'Pass') return 'Met';
        if (status === 'Fail') return 'Not Met';
        return status || 'Unknown';
    }

    get thresholdStatusClass() {
        if (!this._scoreData) return 'slds-dl_horizontal__detail';
        const met = this._scoreData.ThresholdMet__c;
        return met
            ? 'slds-dl_horizontal__detail threshold-met'
            : 'slds-dl_horizontal__detail threshold-not-met';
    }

    // =========================================================================
    // Risk categories (AC-4)
    // =========================================================================

    get riskCategoriesList() {
        if (!this._scoreData || !this._scoreData.RiskCategories__c) return [];
        return this._scoreData.RiskCategories__c
            .split(',')
            .map(c => c.trim())
            .filter(c => c.length > 0);
    }

    get hasRiskCategories() {
        return this.riskCategoriesList.length > 0;
    }
}
