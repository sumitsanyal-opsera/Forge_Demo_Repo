import { createElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import OnboardingCard from 'c/onboardingCard';

const flushPromises = () => new Promise(resolve => setTimeout(resolve, 0));

function createComponent(props = {}) {
    const element = createElement('c-onboarding-card', { is: OnboardingCard });
    element[NavigationMixin.Navigate] = jest.fn();
    if (props.isAdmin !== undefined) {
        element.isAdmin = props.isAdmin;
    }
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
// General rendering
// =============================================================================

describe('rendering', () => {
    it('renders the onboarding card container', () => {
        const element = createComponent();
        const card = element.shadowRoot.querySelector('.onboarding-card');
        expect(card).not.toBeNull();
    });

    it('renders a welcome heading element', () => {
        const element = createComponent();
        const heading = element.shadowRoot.querySelector('h1');
        expect(heading).not.toBeNull();
    });

    it('renders exactly 3 setup step list items', () => {
        const element = createComponent();
        const steps = element.shadowRoot.querySelectorAll('.setup-step');
        expect(steps.length).toBe(3);
    });

    it('renders exactly 3 cloud template cards', () => {
        const element = createComponent();
        const cards = element.shadowRoot.querySelectorAll('.cloud-template-card');
        expect(cards.length).toBe(3);
    });

    it('renders the sample dashboard image by default', () => {
        const element = createComponent();
        const img = element.shadowRoot.querySelector('img.sample-screenshot');
        expect(img).not.toBeNull();
    });

    it('sample image has a non-empty alt attribute for accessibility', () => {
        const element = createComponent();
        const img = element.shadowRoot.querySelector('img.sample-screenshot');
        expect(img.getAttribute('alt')).toBeTruthy();
    });

    it('renders configure button', () => {
        const element = createComponent();
        const btn = element.shadowRoot.querySelector('.configure-btn');
        expect(btn).not.toBeNull();
    });
});

// =============================================================================
// Admin user (isAdmin = true)
// =============================================================================

describe('admin user (isAdmin = true)', () => {
    it('configure button is enabled when isAdmin is true', () => {
        const element = createComponent({ isAdmin: true });
        const btn = element.shadowRoot.querySelector('.configure-btn');
        expect(btn.disabled).toBe(false);
    });

    it('does not show admin-required message for admin', () => {
        const element = createComponent({ isAdmin: true });
        const msg = element.shadowRoot.querySelector('.admin-required-message');
        expect(msg).toBeNull();
    });

    it('clicking configure button calls NavigationMixin.Navigate', async () => {
        const element = createComponent({ isAdmin: true });
        element.shadowRoot.querySelector('.configure-btn').click();
        await flushPromises();

        expect(element[NavigationMixin.Navigate]).toHaveBeenCalledTimes(1);
    });

    it('navigates to the scenarios nav item page', async () => {
        const element = createComponent({ isAdmin: true });
        element.shadowRoot.querySelector('.configure-btn').click();
        await flushPromises();

        expect(element[NavigationMixin.Navigate]).toHaveBeenCalledWith(
            expect.objectContaining({
                type: 'standard__navItemPage',
                attributes: expect.objectContaining({ apiName: 'scenarios' })
            })
        );
    });
});

// =============================================================================
// Viewer user (isAdmin = false / default)
// =============================================================================

describe('viewer user (isAdmin = false)', () => {
    it('configure button is disabled when isAdmin is false', () => {
        const element = createComponent({ isAdmin: false });
        const btn = element.shadowRoot.querySelector('.configure-btn');
        expect(btn.disabled).toBe(true);
    });

    it('shows admin-required message when isAdmin is false', () => {
        const element = createComponent({ isAdmin: false });
        const msg = element.shadowRoot.querySelector('.admin-required-message');
        expect(msg).not.toBeNull();
    });

    it('configure button is disabled by default (no isAdmin prop)', () => {
        const element = createComponent();
        const btn = element.shadowRoot.querySelector('.configure-btn');
        expect(btn.disabled).toBe(true);
    });

    it('does not call NavigationMixin.Navigate when handleConfigure fires for non-admin', async () => {
        const element = createComponent({ isAdmin: false });
        // Programmatically invoke handler since disabled button click is prevented by browser
        element.shadowRoot.querySelector('.configure-btn').dispatchEvent(new MouseEvent('click'));
        await flushPromises();

        expect(element[NavigationMixin.Navigate]).not.toHaveBeenCalled();
    });
});

// =============================================================================
// Cloud template cards
// =============================================================================

describe('cloud template cards', () => {
    it('each cloud template card has an icon element', () => {
        const element = createComponent();
        const icons = element.shadowRoot.querySelectorAll('.cloud-template-card lightning-icon');
        expect(icons.length).toBe(3);
    });

    it('each cloud template card has a heading', () => {
        const element = createComponent();
        const headings = element.shadowRoot.querySelectorAll('.cloud-template-card h3');
        expect(headings.length).toBe(3);
    });

    it('each cloud template card has a description paragraph', () => {
        const element = createComponent();
        const descs = element.shadowRoot.querySelectorAll('.cloud-template-card .slds-card__body p');
        expect(descs.length).toBe(3);
    });
});

// =============================================================================
// Setup steps
// =============================================================================

describe('setup steps', () => {
    it('each step has a step number badge', () => {
        const element = createComponent();
        const badges = element.shadowRoot.querySelectorAll('.setup-step .step-number');
        expect(badges.length).toBe(3);
    });

    it('step numbers are 1, 2, 3', () => {
        const element = createComponent();
        const badges = Array.from(
            element.shadowRoot.querySelectorAll('.setup-step .step-number')
        );
        const numbers = badges.map(b => b.textContent.trim());
        expect(numbers).toEqual(['1', '2', '3']);
    });
});

// =============================================================================
// Image error fallback
// =============================================================================

describe('image error fallback', () => {
    it('shows fallback illustration when image fails to load', async () => {
        const element = createComponent();
        const img = element.shadowRoot.querySelector('img.sample-screenshot');
        img.dispatchEvent(new ErrorEvent('error'));
        await flushPromises();

        const fallback = element.shadowRoot.querySelector('.image-fallback');
        expect(fallback).not.toBeNull();
    });

    it('hides the img element after an image error', async () => {
        const element = createComponent();
        const img = element.shadowRoot.querySelector('img.sample-screenshot');
        img.dispatchEvent(new ErrorEvent('error'));
        await flushPromises();

        const imgAfter = element.shadowRoot.querySelector('img.sample-screenshot');
        expect(imgAfter).toBeNull();
    });
});
