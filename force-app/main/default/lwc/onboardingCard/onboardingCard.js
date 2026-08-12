import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import SampleDashboard from '@salesforce/resourceUrl/SampleDashboard';

import labelWelcomeHeading  from '@salesforce/label/c.Onboarding_WelcomeHeading';
import labelStep1           from '@salesforce/label/c.Onboarding_Step1';
import labelStep2           from '@salesforce/label/c.Onboarding_Step2';
import labelStep3           from '@salesforce/label/c.Onboarding_Step3';
import labelActionButton    from '@salesforce/label/c.Onboarding_ActionButton';
import labelAdminRequired   from '@salesforce/label/c.Onboarding_AdminRequired';
import labelSalesName       from '@salesforce/label/c.Onboarding_SalesCloudName';
import labelSalesDesc       from '@salesforce/label/c.Onboarding_SalesCloudDesc';
import labelServiceName     from '@salesforce/label/c.Onboarding_ServiceCloudName';
import labelServiceDesc     from '@salesforce/label/c.Onboarding_ServiceCloudDesc';
import labelExperienceName  from '@salesforce/label/c.Onboarding_ExperienceCloudName';
import labelExperienceDesc  from '@salesforce/label/c.Onboarding_ExperienceCloudDesc';

const CLOUD_TEMPLATES = [
    {
        key:         'sales',
        icon:        'standard:account',
        name:        labelSalesName,
        description: labelSalesDesc
    },
    {
        key:         'service',
        icon:        'standard:case',
        name:        labelServiceName,
        description: labelServiceDesc
    },
    {
        key:         'experience',
        icon:        'standard:experience_cloud',
        name:        labelExperienceName,
        description: labelExperienceDesc
    }
];

const SETUP_STEPS = [
    { key: '1', number: '1', text: labelStep1 },
    { key: '2', number: '2', text: labelStep2 },
    { key: '3', number: '3', text: labelStep3 }
];

export default class OnboardingCard extends NavigationMixin(LightningElement) {
    @api isAdmin = false;

    sampleDashboardUrl = SampleDashboard;
    imageLoadError     = false;

    label = {
        welcomeHeading: labelWelcomeHeading,
        actionButton:   labelActionButton,
        adminRequired:  labelAdminRequired
    };

    cloudTemplates = CLOUD_TEMPLATES;
    steps          = SETUP_STEPS;

    get configButtonDisabled() {
        return !this.isAdmin;
    }

    get configButtonTitle() {
        return this.isAdmin ? '' : labelAdminRequired;
    }

    handleConfigure() {
        if (!this.isAdmin) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'scenarios' }
        });
    }

    handleImageError() {
        this.imageLoadError = true;
    }
}
