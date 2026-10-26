import { BrowserRouter, Route, Routes } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { configured } from "./lib/supabase";
import { StoreProvider } from "./lib/store";
import { FullPage, Spinner } from "./components/ui";
import Home from "./pages/Home";
import Menu from "./pages/Menu";
import Checkout from "./pages/Checkout";
import OrderStatus from "./pages/OrderStatus";
import AdminShell, { RequireStaff } from "./pages/admin/AdminShell";
import Board from "./pages/admin/Board";
import Prep from "./pages/admin/Prep";
import MenuAdmin from "./pages/admin/MenuAdmin";
import Sales from "./pages/admin/Sales";

const queryClient = new QueryClient({ defaultOptions: { queries: { retry: 1, refetchOnWindowFocus: true } } });

function StoreFallback(state: "loading" | "missing" | "error") {
  if (state === "loading") return <Spinner />;
  if (state === "missing") return <FullPage title="Store not found">Check the web address. Add <code>?tenant=aryas</code> when testing a preview link.</FullPage>;
  return <FullPage title="We can't load the store">Check your connection and refresh the page.</FullPage>;
}

export default function App() {
  if (!configured) {
    return <FullPage title="Almost there">Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY (see README), then reload.</FullPage>;
  }
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Routes>
          {/* Staff: owner / manager / kitchen (login required) */}
          <Route path="/admin" element={<AdminShell />}>
            <Route index element={<Board />} />
            <Route path="prep" element={<Prep />} />
            <Route path="menu" element={<MenuAdmin />} />
            <Route path="sales" element={<Sales />} />
          </Route>
          <Route path="/kitchen" element={<RequireStaff><Board kitchen /></RequireStaff>} />

          {/* Customers (no login) */}
          <Route path="/*" element={
            <StoreProvider fallback={StoreFallback}>
              <Routes>
                <Route index element={<Home />} />
                <Route path="order/:token" element={<OrderStatus />} />
                <Route path=":brandSlug" element={<Menu />} />
                <Route path=":brandSlug/checkout" element={<Checkout />} />
                <Route path="*" element={<FullPage title="Page not found" />} />
              </Routes>
            </StoreProvider>
          } />
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  );
}
