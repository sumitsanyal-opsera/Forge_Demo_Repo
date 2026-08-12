import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { PipelineDetailPage } from './pages/PipelineDetailPage.js';

const root = document.getElementById('root');
if (!root) throw new Error('Root element not found');

createRoot(root).render(
  <StrictMode>
    <BrowserRouter>
      <Routes>
        <Route path="/pipelines/:id" element={<PipelineDetailPage />} />
        <Route path="*" element={<Navigate to="/pipelines/demo" replace />} />
      </Routes>
    </BrowserRouter>
  </StrictMode>,
);
