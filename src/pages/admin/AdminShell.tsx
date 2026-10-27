import { createContext, useContext, useEffect, useState, type FormEvent, type ReactNode } from "react";
import { NavLink, Outlet } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "../../lib/supabase";
import { Notice, Spinner } from "../../components/ui";

export type Membership = { tenantId: string; slug: string; name: string; role: "owner" | "manager" | "kitchen_staff" | "super_admin"; timezone: string; currency: string };
const AdminContext = createContext<{ member: Membership; isManager: boolean; session: Session } | null>(null);
export const useAdmin = () => {
  const c = useContext(AdminContext);
  if (!c) throw new Error("useAdmin outside AdminShell");
  return c;
};

export function useSession() {
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_e, s) => setSession(s));
    return () => data.subscription.unsubscribe();
  }, []);
  return session;
}

function Login() {
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"idle" | "sending" | "sent" | "error">("idle");
  async function submit(e: FormEvent) {
    e.preventDefault();
    setState("sending");
    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim(),
      options: { emailRedirectTo: window.location.href, shouldCreateUser: false },
    });
    setState(error ? "error" : "sent");
  }
  return (
    <main className="wrap flex min-h-[80vh] max-w-sm flex-col justify-center gap-4">
      <h1 className="h-display text-3xl">Staff sign in</h1>
      {state === "sent" ? (
        <Notice tone="ok">Check {email} for a sign-in link. Open it on this device.</Notice>
      ) : (
        <form onSubmit={submit} className="flex flex-col gap-3">
          <label className="label" htmlFor="staff-email">Work email</label>
          <input id="staff-email" className="input" type="email" required autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} />
          {state === "error" && <Notice tone="error">That email isn't set up for staff access. Ask the owner to add you.</Notice>}
          <button className="btn-primary" disabled={state === "sending"}>{state === "sending" ? "Sending…" : "Email me a sign-in link"}</button>
        </form>
      )}
    </main>
  );
}

export function RequireStaff({ children }: { children: ReactNode }) {
  const session = useSession();
  const memberships = useQuery({
    queryKey: ["my-tenants", session?.user.id],
    enabled: Boolean(session),
    queryFn: async () => {
      const { data, error } = await supabase.rpc("my_tenants");
      if (error) throw error;
      return data as Membership[];
    },
  });
  const [picked, setPicked] = useState<string | null>(() => {
    try { return localStorage.getItem("kos:admin-tenant"); } catch { return null; }
  });

  if (session === undefined || (session && memberships.isLoading)) return <Spinner />;
  if (!session) return <Login />;
  const list = memberships.data ?? [];
  if (list.length === 0) {
    return (
      <main className="wrap max-w-md py-16">
        <Notice tone="warn">Your account ({session.user.email}) isn't linked to a kitchen yet. Ask the owner to add you.</Notice>
        <button className="btn mt-4" onClick={() => supabase.auth.signOut()}>Sign out</button>
      </main>
    );
  }
  const member = list.find((m) => m.tenantId === picked) ?? list[0];
  const isManager = member.role !== "kitchen_staff";
  return (
    <AdminContext.Provider value={{ member, isManager, session }}>
      {list.length > 1 && (
        <div className="wrap pt-2">
          <select aria-label="Kitchen" className="input max-w-xs" value={member.tenantId}
            onChange={(e) => { setPicked(e.target.value); try { localStorage.setItem("kos:admin-tenant", e.target.value); } catch { /* ignore */ } }}>
            {list.map((m) => <option key={m.tenantId} value={m.tenantId}>{m.name}</option>)}
          </select>
        </div>
      )}
      {children}
    </AdminContext.Provider>
  );
}

/** Owner / manager only pages (e.g. Menu manager). Kitchen staff see a short note instead. */
export function RequireManager({ children }: { children: ReactNode }) {
  const { isManager } = useAdmin();
  if (!isManager) return <main className="wrap max-w-md py-16"><Notice tone="warn">Only owners and managers can open this page.</Notice></main>;
  return <>{children}</>;
}

export default function AdminShell() {
  return (
    <RequireStaff>
      <AdminNav />
      <Outlet />
    </RequireStaff>
  );
}

function AdminNav() {
  const { member, isManager, session } = useAdmin();
  const link = ({ isActive }: { isActive: boolean }) => `chip ${isActive ? "!bg-fg !text-bg !border-transparent" : ""}`;
  return (
    <header className="border-b border-line bg-surface" style={{ paddingTop: "env(safe-area-inset-top)" }}>
      <div className="wrap flex flex-wrap items-center gap-2 py-3">
        <span className="mr-2 h-display text-xl">{member.name}</span>
        <nav className="flex flex-wrap gap-2">
          <NavLink to="/admin" end className={link}>Orders</NavLink>
          <NavLink to="/admin/prep" className={link}>Prep list</NavLink>
          {isManager && <NavLink to="/admin/menu" className={link}>Menu</NavLink>}
          {isManager && <NavLink to="/admin/sales" className={link}>Sales</NavLink>}
          <NavLink to="/kitchen" className={link}>Kitchen screen</NavLink>
        </nav>
        <span className="flex-1" />
        <span className="text-sm text-muted">{session.user.email} · {member.role.replace("_", " ")}</span>
        <button className="btn min-h-[36px] text-sm" onClick={() => supabase.auth.signOut()}>Sign out</button>
      </div>
    </header>
  );
}

export { NavLink };
