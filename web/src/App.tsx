import { NavLink, Navigate, Route, Routes } from "react-router-dom";
import { useAuth } from "./auth/AuthProvider";
import { Loading } from "./components/ui";
import SignIn from "./screens/SignIn";
import Home from "./screens/Home";
import Teams from "./screens/Teams";
import TeamDetail from "./screens/TeamDetail";
import NewEvent from "./screens/NewEvent";
import EventDetail from "./screens/EventDetail";

function TabBar() {
  const tab = (to: string, label: string, path: string) => (
    <NavLink to={to} className={({ isActive }) => (isActive ? "active" : "")} end={to === "/"}>
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d={path} />
      </svg>
      {label}
    </NavLink>
  );
  return (
    <nav className="tabbar">
      {tab("/", "Home", "M3 11l9-8 9 8M5 10v10h14V10")}
      {tab("/teams", "Teams", "M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M9 7a4 4 0 1 0 0 .01M23 21v-2a4 4 0 0 0-3-3.87")}
      {tab("/new", "New", "M12 5v14M5 12h14")}
    </nav>
  );
}

export default function App() {
  const { session, loading } = useAuth();
  if (loading) return <Loading />;
  if (!session) return <SignIn />;

  return (
    <>
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/teams" element={<Teams />} />
        <Route path="/teams/:teamId" element={<TeamDetail />} />
        <Route path="/new" element={<NewEvent />} />
        <Route path="/events/:eventId" element={<EventDetail />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      <TabBar />
    </>
  );
}
