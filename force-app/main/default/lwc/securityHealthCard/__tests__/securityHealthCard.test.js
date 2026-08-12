import { createElement } from 'lwc';
import SecurityHealthCard from 'c/securityHealthCard';
import getLatestSecurityScore from '@salesforce/apex/SmokeTestSecurityController.getLatestSecurityScore';

import mockHighScore    from './data/highScore.json';
import mockLowScore     from './data/lowScore.json';
import mockNoBaseline   from './data/noBaseline.json';
import mockPerfectScore from './data/perfectScore.json';
import mockZeroScore    from './data/zeroScore.json';

const GAUGE_RADIUS        = 50;
const GAUGE_CIRCUMFERENCE = 2 * Math.PI * GAUGE_RADIUS;

const flushPromises = () => new Promise(resolve => setTimeout(resolve, 0));

function createComponent(props = {}) {
    const element = createElement('c-security-health-card', { is: SecurityHealthCard });
    Object.assign(element, props);
    document.body.appendChild(element);
    return element;
}

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
});

// =============================================================================
// Permission gating (AC-5)
// =============================================================================

describe('permission gating', () => {
    it('renders no markup when isAdmin is false (default)', () => {
        const element = createComponent();
        // No inner card should be present
        const card = element.shadowRoot.querySelector('.slds-card');
        expect(card).toBeNull();
    });

    it('renders no markup when isAdmin is explicitly false', () => {
        const element = createComponent({ isAdmin: false });
        const card = element.shadowRoot.querySelector('.slds-card');
        expect(card).toBeNull();
    });

    it('does not call Apex when isAdmin is false', () => {
        createComponent({ isAdmin: false });
        expect(getLatestSecurityScore).not.toHaveBeenCalled();
    });

    it('calls Apex and renders card when isAdmin is true', async () => {
        getLatestSecurityScore.mockResolvedValue(mockHighScore);
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        expect(getLatestSecurityScore).toHaveBeenCalledTimes(1);
        const card = element.shadowRoot.querySelector('.slds-card');
        expect(card).not.toBeNull();
    });
});

// =============================================================================
// SVG gauge ring — score boundaries (AC-1, AC-6)
// =============================================================================

describe('SVG gauge ring', () => {
    it('renders SVG with role=img (AC-6)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockHighScore);
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const svg = element.shadowRoot.querySelector('svg');
        expect(svg).not.toBeNull();
        expect(svg.getAttribute('role')).toBe('img');
    });

    it('renders aria-label containing post-deployment score (AC-6)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockHighScore); // PostDeploymentScore__c = 90
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const svg = element.shadowRoot.querySelector('svg');
        expect(svg.getAttribute('aria-label')).toContain('90');
        expect(svg.getAttribute('aria-label')).toContain('out of 100');
    });

    it('renders visually hidden assistive text with score (AC-6)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockHighScore);
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const assistiveText = element.shadowRoot.querySelector('.slds-assistive-text');
        expect(assistiveText).not.toBeNull();
        expect(assistiveText.textContent).toContain('90');
    });

    it('renders gauge with correct stroke-dashoffset for score 100 (AC-1)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockPerfectScore); // PostDeploymentScore__c = 100
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const fgCircle = element.shadowRoot.querySelector('.gauge-fg');
        expect(fgCircle).not.toBeNull();
        const dashoffset = parseFloat(fgCircle.getAttribute('stroke-dashoffset'));
        // Score 100 → offset = 0 (fully filled)
        expect(dashoffset).toBeCloseTo(0, 1);
    });

    it('renders gauge with correct stroke-dashoffset for score 0 (AC-1)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockZeroScore); // PostDeploymentScore__c = 0
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const fgCircle = element.shadowRoot.querySelector('.gauge-fg');
        const dashoffset = parseFloat(fgCircle.getAttribute('stroke-dashoffset'));
        // Score 0 → offset = full circumference (empty ring)
        expect(dashoffset).toBeCloseTo(GAUGE_CIRCUMFERENCE, 1);
    });

    it('renders gauge with correct stroke-dashoffset for score 50 (AC-1)', async () => {
        const halfScore = { ...mockHighScore, PostDeploymentScore__c: 50 };
        getLatestSecurityScore.mockResolvedValue(halfScore);
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const fgCircle = element.shadowRoot.querySelector('.gauge-fg');
        const dashoffset = parseFloat(fgCircle.getAttribute('stroke-dashoffset'));
        const expected = GAUGE_CIRCUMFERENCE * 0.5;
        expect(dashoffset).toBeCloseTo(expected, 1);
    });

    it('renders gauge with correct stroke-dashoffset for score 80 (AC-1)', async () => {
        const eightyScore = { ...mockHighScore, PostDeploymentScore__c: 80 };
        getLatestSecurityScore.mockResolvedValue(eightyScore);
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const fgCircle = element.shadowRoot.querySelector('.gauge-fg');
        const dashoffset = parseFloat(fgCircle.getAttribute('stroke-dashoffset'));
        const expected = GAUGE_CIRCUMFERENCE * 0.2;
        expect(dashoffset).toBeCloseTo(expected, 1);
    });

    it('applies green class when score meets threshold (AC-1)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockHighScore); // score 90 >= threshold 80
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const fgCircle = element.shadowRoot.querySelector('.gauge-fg');
        expect(fgCircle.classList.contains('gauge-green')).toBe(true);
    });

    it('applies red class when score is below threshold (AC-1)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockLowScore); // score 60 < threshold 80
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const fgCircle = element.shadowRoot.querySelector('.gauge-fg');
        expect(fgCircle.classList.contains('gauge-red')).toBe(true);
    });

    it('applies yellow class when score is within 5 points of threshold (AC-1)', async () => {
        const nearThreshold = { ...mockLowScore, PostDeploymentScore__c: 76, ScoreDelta__c: -9 };
        getLatestSecurityScore.mockResolvedValue(nearThreshold); // 76 = threshold(80) - 4
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const fgCircle = element.shadowRoot.querySelector('.gauge-fg');
        expect(fgCircle.classList.contains('gauge-yellow')).toBe(true);
    });
});

// =============================================================================
// Score comparison section (AC-2)
// =============================================================================

describe('score comparison', () => {
    it('displays pre-deployment and post-deployment scores (AC-2)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockHighScore); // pre=88, post=90
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const bodyText = element.shadowRoot.querySelector('.slds-card__body').textContent;
        expect(bodyText).toContain('88');
        expect(bodyText).toContain('90');
    });

    it('shows "No baseline available" when pre-score is null (edge case)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockNoBaseline); // PreDeploymentScore__c = null
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const bodyText = element.shadowRoot.querySelector('.slds-card__body').textContent;
        expect(bodyText).toContain('No baseline available');
    });

    it('displays threshold value (AC-2)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockHighScore); // AbsoluteThreshold__c = 80
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const bodyText = element.shadowRoot.querySelector('.slds-card__body').textContent;
        expect(bodyText).toContain('80');
    });

    it('displays threshold status "Met" when ThresholdMet__c is true (AC-2)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockHighScore); // ThresholdMet__c = true
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const bodyText = element.shadowRoot.querySelector('.slds-card__body').textContent;
        expect(bodyText).toContain('Met');
    });

    it('displays threshold status "Not Met" when ThresholdMet__c is false (AC-2)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockLowScore); // ThresholdMet__c = false
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const bodyText = element.shadowRoot.querySelector('.slds-card__body').textContent;
        expect(bodyText).toContain('Not Met');
    });
});

// =============================================================================
// Delta display (AC-3)
// =============================================================================

describe('delta display', () => {
    it('shows positive delta in green with arrowup icon (AC-3)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockHighScore); // ScoreDelta__c = +2
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const deltaCell = element.shadowRoot.querySelector('.delta-positive');
        expect(deltaCell).not.toBeNull();

        const icon = deltaCell.querySelector('lightning-icon');
        expect(icon).not.toBeNull();
        expect(icon.iconName).toBe('utility:arrowup');
    });

    it('shows negative delta in red with arrowdown icon (AC-3)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockLowScore); // ScoreDelta__c = -25
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const deltaCell = element.shadowRoot.querySelector('.delta-negative');
        expect(deltaCell).not.toBeNull();

        const icon = deltaCell.querySelector('lightning-icon');
        expect(icon).not.toBeNull();
        expect(icon.iconName).toBe('utility:arrowdown');
    });

    it('shows N/A and no icon when delta is null (no baseline)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockNoBaseline); // ScoreDelta__c = null
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const bodyText = element.shadowRoot.querySelector('.slds-card__body').textContent;
        expect(bodyText).toContain('N/A');
    });

    it('formats positive delta with leading plus sign (AC-3)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockHighScore); // ScoreDelta__c = 2
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const bodyText = element.shadowRoot.querySelector('.slds-card__body').textContent;
        expect(bodyText).toContain('+2');
    });

    it('formats negative delta with minus sign (AC-3)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockLowScore); // ScoreDelta__c = -25
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const bodyText = element.shadowRoot.querySelector('.slds-card__body').textContent;
        expect(bodyText).toContain('-25');
    });
});

// =============================================================================
// Risk categories (AC-4)
// =============================================================================

describe('risk categories', () => {
    it('renders list items for each risk category (AC-4)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockLowScore);
        // RiskCategories__c = "Password Policies,Session Settings,Network Access"
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const listItems = element.shadowRoot.querySelectorAll('.slds-list_dotted li');
        expect(listItems.length).toBe(3);
    });

    it('renders each category name in the list (AC-4)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockLowScore);
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const bodyText = element.shadowRoot.querySelector('.slds-card__body').textContent;
        expect(bodyText).toContain('Password Policies');
        expect(bodyText).toContain('Session Settings');
        expect(bodyText).toContain('Network Access');
    });

    it('shows "No risk category changes detected" when RiskCategories__c is null (edge case)', async () => {
        getLatestSecurityScore.mockResolvedValue(mockHighScore); // RiskCategories__c = null
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const bodyText = element.shadowRoot.querySelector('.slds-card__body').textContent;
        expect(bodyText).toContain('No risk category changes detected');
    });

    it('shows "No risk category changes detected" when RiskCategories__c is empty', async () => {
        const emptyCategories = { ...mockHighScore, RiskCategories__c: '' };
        getLatestSecurityScore.mockResolvedValue(emptyCategories);
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const bodyText = element.shadowRoot.querySelector('.slds-card__body').textContent;
        expect(bodyText).toContain('No risk category changes detected');
    });

    it('trims whitespace from comma-separated category names', async () => {
        const spacedCategories = { ...mockLowScore, RiskCategories__c: ' Sharing Settings , Login Flows ' };
        getLatestSecurityScore.mockResolvedValue(spacedCategories);
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const listItems = element.shadowRoot.querySelectorAll('.slds-list_dotted li');
        expect(listItems.length).toBe(2);
        expect(listItems[0].textContent).toBe('Sharing Settings');
        expect(listItems[1].textContent).toBe('Login Flows');
    });
});

// =============================================================================
// Error handling
// =============================================================================

describe('error state', () => {
    it('shows error message when Apex throws (AC-1)', async () => {
        getLatestSecurityScore.mockRejectedValue(new Error('Insufficient access'));
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const errorBanner = element.shadowRoot.querySelector('.slds-alert_warning');
        expect(errorBanner).not.toBeNull();
        expect(errorBanner.textContent).toContain('Security score unavailable');
    });

    it('renders the card shell even when Apex fails', async () => {
        getLatestSecurityScore.mockRejectedValue(new Error('Network error'));
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const card = element.shadowRoot.querySelector('.slds-card');
        expect(card).not.toBeNull();
    });

    it('does not render SVG gauge when Apex fails', async () => {
        getLatestSecurityScore.mockRejectedValue(new Error('Network error'));
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const svg = element.shadowRoot.querySelector('.gauge-fg');
        expect(svg).toBeNull();
    });
});

// =============================================================================
// Null / empty Apex response
// =============================================================================

describe('null response (no data)', () => {
    it('shows no-data message when Apex returns null', async () => {
        getLatestSecurityScore.mockResolvedValue(null);
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const bodyText = element.shadowRoot.querySelector('.slds-card__body').textContent;
        expect(bodyText).toContain('No security score data available');
    });

    it('does not render SVG when data is null', async () => {
        getLatestSecurityScore.mockResolvedValue(null);
        const element = createComponent({ isAdmin: true });
        await flushPromises();

        const gauge = element.shadowRoot.querySelector('.gauge-fg');
        expect(gauge).toBeNull();
    });
});
