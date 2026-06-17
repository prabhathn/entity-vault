import { BrowserRouter, Routes, Route, NavLink } from 'react-router-dom';
import ResolvePage from './pages/ResolvePage';
import EncodePage from './pages/EncodePage';
import TranscodePage from './pages/TranscodePage';
import EnrichOutPage from './pages/EnrichOutPage';
import EnrichInPage from './pages/EnrichInPage';
import ContributionsPage from './pages/ContributionsPage';
import EntitiesPage from './pages/EntitiesPage';
import GroupsPage from './pages/GroupsPage';
import NamespacesPage from './pages/NamespacesPage';
import AuditPage from './pages/AuditPage';
import './App.css';

function App() {
  return (
    <BrowserRouter>
      <div className="app-layout">
        <nav className="sidebar">
          <h2>Entity Vault</h2>
          <ul>
            <li><NavLink to="/">Resolve</NavLink></li>
            <li><NavLink to="/encode">Encode</NavLink></li>
            <li><NavLink to="/transcode">Transcode</NavLink></li>
            <li><NavLink to="/enrich-out">Enrich Out</NavLink></li>
            <li><NavLink to="/enrich-in">Enrich In</NavLink></li>
            <li><NavLink to="/create-group">Create Group</NavLink></li>
            <li className="separator" />
            <li><NavLink to="/entities">Entities</NavLink></li>
            <li><NavLink to="/groups">Groups</NavLink></li>
            <li><NavLink to="/namespaces">Namespaces</NavLink></li>
            <li><NavLink to="/audit">Audit Log</NavLink></li>
          </ul>
        </nav>
        <main className="content">
          <Routes>
            <Route path="/" element={<ResolvePage />} />
            <Route path="/encode" element={<EncodePage />} />
            <Route path="/transcode" element={<TranscodePage />} />
            <Route path="/enrich-out" element={<EnrichOutPage />} />
            <Route path="/enrich-in" element={<ContributionsPage />} />
            <Route path="/create-group" element={<EnrichInPage />} />
            <Route path="/entities" element={<EntitiesPage />} />
            <Route path="/groups" element={<GroupsPage />} />
            <Route path="/namespaces" element={<NamespacesPage />} />
            <Route path="/audit" element={<AuditPage />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  );
}

export default App;
