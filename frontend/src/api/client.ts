export const api = {
  ingest: (mutations: any[], auth?: { challenge_id: string; signature: string }) => {
    return fetch(`/api/electric/v1/ingest`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mutations, ...(auth ? { auth } : {}) }),
    });
  },
};
