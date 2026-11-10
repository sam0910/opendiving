# Sam's notes

## Signed-out visitors and the seafloor view (2026-11-10)

**Decision: signed-in users only.** The Seafloor explorer asks signed-out visitors to sign in.

The new seafloor service in the API only answers signed-in users, so visitors who aren't logged in lose the 3D
seafloor view.

- Before the move, the Seafloor explorer page (`localhost:3000/seascape-map`) got its depth data from the web app
  itself, and anyone could use it.
- The new API version (`/api/v1/seafloor`) follows the same rules as the place-search endpoint. **You must be signed
  in**, or it answers **401**. Each account gets **120 lookups an hour**.
- That protects the daily KHOA allowance (10,000 requests a day, shared by every account) from strangers. But once
  the web app switches to the API, a signed-out visitor's map gets no depth data.
- The alternative, not chosen: a limited version for signed-out visitors, for example one capped per IP address.
