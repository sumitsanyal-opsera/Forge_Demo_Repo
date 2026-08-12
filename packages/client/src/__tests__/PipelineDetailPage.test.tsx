import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { http, HttpResponse } from 'msw';
import { setupServer } from 'msw/node';
import { describe, it, expect, beforeAll, afterAll, afterEach } from 'vitest';
import { PipelineDetailPage } from '../pages/PipelineDetailPage.js';
import type { PipelineDetail } from '../types/pipeline.js';

// ─── Fixtures ─────────────────────────────────────────────────────────────────

import monitoringFixture from '../../../../test/fixtures/client/pipeline/monitoring.json';
import resolvedFixture from '../../../../test/fixtures/client/pipeline/resolved.json';
import noBaselineFixture from '../../../../test/fixtures/client/pipeline/no_baseline.json';
import noMetadataFixture from '../../../../test/fixtures/client/pipeline/no_metadata.json';
import confirmedStuckFixture from '../../../../test/fixtures/client/pipeline/confirmed_stuck.json';

// ─── MSW server ───────────────────────────────────────────────────────────────

const server = setupServer();

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

// ─── Render helper ────────────────────────────────────────────────────────────

function renderPage(id: string) {
  return render(
    <MemoryRouter initialEntries={[`/pipelines/${id}`]}>
      <Routes>
        <Route path="/pipelines/:id" element={<PipelineDetailPage />} />
      </Routes>
    </MemoryRouter>,
  );
}

function mockSuccess(id: string, fixture: PipelineDetail) {
  server.use(
    http.get(`/api/v1/pipelines/${id}`, () =>
      HttpResponse.json(fixture),
    ),
  );
}

function mock404(id: string) {
  server.use(
    http.get(`/api/v1/pipelines/${id}`, () =>
      new HttpResponse(null, { status: 404 }),
    ),
  );
}

function mockError(id: string) {
  server.use(
    http.get(`/api/v1/pipelines/${id}`, () =>
      new HttpResponse(null, { status: 500, statusText: 'Internal Server Error' }),
    ),
  );
}

// ─── Integration tests ────────────────────────────────────────────────────────

describe('PipelineDetailPage', () => {
  describe('loading state', () => {
    it('shows loading skeleton while request is in-flight', () => {
      let resolve: () => void;
      server.use(
        http.get('/api/v1/pipelines/pipe-loading', () =>
          new Promise<Response>((r) => {
            resolve = () => r(HttpResponse.json(monitoringFixture) as unknown as Response);
          }),
        ),
      );
      renderPage('pipe-loading');
      expect(screen.getByTestId('loading-skeleton')).toBeInTheDocument();
      // Cleanup: resolve the pending promise
      resolve!();
    });
  });

  describe('successful render — monitoring state', () => {
    beforeAll(() => mockSuccess('pipe-001', monitoringFixture as unknown as PipelineDetail));

    it('renders the pipeline name in the header', async () => {
      renderPage('pipe-001');
      await waitFor(() =>
        expect(screen.getByTestId('pipeline-name')).toBeInTheDocument(),
      );
      expect(screen.getByTestId('pipeline-name').textContent).toContain(
        monitoringFixture.name,
      );
    });

    it('renders the detection state badge', async () => {
      renderPage('pipe-001');
      await waitFor(() =>
        expect(screen.getByTestId('detection-state-badge')).toBeInTheDocument(),
      );
      expect(screen.getByTestId('detection-state-badge').textContent).toBe('Monitoring');
    });

    it('renders the org name meta info', async () => {
      renderPage('pipe-001');
      await waitFor(() =>
        expect(screen.getByTestId('org-name')).toBeInTheDocument(),
      );
    });

    it('renders the deploy ID meta info', async () => {
      renderPage('pipe-001');
      await waitFor(() =>
        expect(screen.getByTestId('deploy-id')).toBeInTheDocument(),
      );
    });

    it('renders 5 state machine nodes', async () => {
      renderPage('pipe-001');
      await waitFor(() =>
        expect(screen.getAllByRole('listitem')).toHaveLength(5),
      );
    });

    it('renders 6 metric cards', async () => {
      renderPage('pipe-001');
      await waitFor(() =>
        expect(screen.getByText('Current Duration')).toBeInTheDocument(),
      );
      expect(screen.getByText('P50 Baseline')).toBeInTheDocument();
      expect(screen.getByText('P90 Baseline')).toBeInTheDocument();
      expect(screen.getByText('P99 Baseline')).toBeInTheDocument();
      expect(screen.getByText('Stale Duration')).toBeInTheDocument();
      expect(screen.getByText('Component Count')).toBeInTheDocument();
    });

    it('renders Timeline tab content by default', async () => {
      renderPage('pipe-001');
      await waitFor(() =>
        expect(screen.getByTestId('panel-timeline')).toBeInTheDocument(),
      );
      expect(screen.getByTestId('panel-timeline')).not.toHaveAttribute('hidden');
    });

    it('switches to Metadata tab on click', async () => {
      renderPage('pipe-001');
      await waitFor(() =>
        expect(screen.getByRole('tab', { name: 'Metadata' })).toBeInTheDocument(),
      );
      await userEvent.click(screen.getByRole('tab', { name: 'Metadata' }));
      expect(screen.getByTestId('panel-metadata')).not.toHaveAttribute('hidden');
      expect(screen.getByTestId('panel-timeline')).toHaveAttribute('hidden');
    });

    it('shows Resume and Cancel buttons (disabled — P3 scope)', async () => {
      renderPage('pipe-001');
      await waitFor(() =>
        expect(screen.getByRole('button', { name: /resume/i })).toBeInTheDocument(),
      );
      expect(screen.getByRole('button', { name: /resume/i })).toBeDisabled();
      expect(screen.getByRole('button', { name: /cancel/i })).toBeDisabled();
    });
  });

  describe('successful render — resolved state', () => {
    beforeAll(() => mockSuccess('pipe-005', resolvedFixture as unknown as PipelineDetail));

    it('shows Resolved badge', async () => {
      renderPage('pipe-005');
      await waitFor(() =>
        expect(screen.getByTestId('detection-state-badge')).toHaveTextContent('Resolved'),
      );
    });

    it('all four pre-resolved nodes are completed', async () => {
      renderPage('pipe-005');
      await waitFor(() =>
        expect(screen.getAllByRole('listitem')).toHaveLength(5),
      );
      const nodes = screen.getAllByRole('listitem');
      for (let i = 0; i < 4; i++) {
        expect(nodes[i]).toHaveAttribute('data-variant', 'completed');
      }
    });
  });

  describe('successful render — confirmed_stuck state', () => {
    beforeAll(() =>
      mockSuccess('pipe-004', confirmedStuckFixture as unknown as PipelineDetail),
    );

    it('Current Duration card has red highlight', async () => {
      const { container } = renderPage('pipe-004');
      await waitFor(() =>
        expect(screen.getByText('Current Duration')).toBeInTheDocument(),
      );
      const redCard = container.querySelector('[data-highlight="red"]');
      expect(redCard).toBeTruthy();
    });
  });

  describe('no_baseline fixture', () => {
    beforeAll(() => mockSuccess('pipe-006', noBaselineFixture as unknown as PipelineDetail));

    it('shows Pending for P50, P90, P99 cards', async () => {
      renderPage('pipe-006');
      await waitFor(() =>
        expect(screen.getByText('P50 Baseline')).toBeInTheDocument(),
      );
      const pending = screen.getAllByText('Pending');
      expect(pending.length).toBeGreaterThanOrEqual(3);
    });

    it('no threshold highlight on Current Duration when baselines are null', async () => {
      const { container } = renderPage('pipe-006');
      await waitFor(() =>
        expect(screen.getByText('Current Duration')).toBeInTheDocument(),
      );
      expect(container.querySelector('[data-highlight]')).toBeNull();
    });
  });

  describe('no_metadata fixture', () => {
    beforeAll(() => mockSuccess('pipe-007', noMetadataFixture as unknown as PipelineDetail));

    it('shows empty metadata message in Metadata tab', async () => {
      renderPage('pipe-007');
      await waitFor(() =>
        expect(screen.getByRole('tab', { name: 'Metadata' })).toBeInTheDocument(),
      );
      await userEvent.click(screen.getByRole('tab', { name: 'Metadata' }));
      await waitFor(() =>
        expect(screen.getByTestId('empty-metadata')).toBeInTheDocument(),
      );
    });
  });

  describe('error state', () => {
    it('shows error state when API returns 500', async () => {
      mockError('pipe-err');
      renderPage('pipe-err');
      await waitFor(() =>
        expect(screen.getByTestId('error-state')).toBeInTheDocument(),
      );
    });
  });

  describe('404 / not found state', () => {
    it('shows not-found state when API returns 404', async () => {
      mock404('pipe-404');
      renderPage('pipe-404');
      await waitFor(() =>
        expect(screen.getByTestId('not-found-state')).toBeInTheDocument(),
      );
    });

    it('not-found state includes the pipeline ID', async () => {
      mock404('pipe-missing');
      renderPage('pipe-missing');
      await waitFor(() =>
        expect(screen.getByTestId('not-found-state')).toBeInTheDocument(),
      );
      expect(screen.getByTestId('not-found-state').textContent).toContain('pipe-missing');
    });
  });
});
