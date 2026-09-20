import { Navigate, Route, Routes } from 'react-router-dom';

import Layout from './components/Layout.jsx';
import { AuthProvider, useAuth } from './lib/AuthContext.jsx';
import Login from './pages/Login.jsx';
import ServerDetail from './pages/ServerDetail.jsx';
import Servers from './pages/Servers.jsx';
import VlanEditor from './pages/VlanEditor.jsx';
import VlanList from './pages/VlanList.jsx';

function RequireAuth({ children }) {
  const { user } = useAuth();
  if (user === undefined) return <p className="p-6 text-ink-muted">กำลังตรวจสอบสิทธิ์...</p>;
  if (user === null) return <Navigate to="/login" replace />;
  return children;
}

function AppRoutes() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route
        path="/"
        element={
          <RequireAuth>
            <Layout />
          </RequireAuth>
        }
      >
        <Route index element={<Navigate to="/servers" replace />} />
        <Route path="dashboard" element={<p className="text-ink-muted">Dashboard — งานถัดไป</p>} />
        <Route path="servers" element={<Servers />} />
        <Route path="servers/:serverId" element={<ServerDetail />} />
        <Route path="vlans" element={<VlanList />} />
        <Route path="vlans/:vlanId" element={<VlanEditor />} />
      </Route>
    </Routes>
  );
}

export default function App() {
  return (
    <AuthProvider>
      <AppRoutes />
    </AuthProvider>
  );
}
