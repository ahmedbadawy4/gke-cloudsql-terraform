# Application

A small Express service written in TypeScript. It is the workload for the GKE and Cloud SQL setup in the root of this repository.

## Run it locally

You need Node.js 24.

```bash
npm ci
npm run start:dev
```

Open `http://localhost:3000`. `nodemon` restarts the server when a file changes.

## Build and run the compiled code

```bash
npm run build
npm start
```

`npm run build` writes the JavaScript to `build/`. `npm start` runs `build/index.js`.

## Endpoints

| Path | Answer |
| --- | --- |
| `/` | A plain text message |
| `/healthz` | `200` with `{"status":"ok"}`. Used as the liveness probe. |
| `/readyz` | `200` with `{"status":"ready"}`, and `503` after the process gets SIGTERM. Used as the readiness probe. |
| `/users/:userId` | The path parameters as JSON |
| any other path | `404` with `{"error":"not found"}` |

Requests are logged to the console. The two health paths are not logged.

## Settings

| Variable | Default | Meaning |
| --- | --- | --- |
| `PORT` | `3000` | Port the server listens on |

On SIGTERM the server stops reporting ready, finishes open requests and exits.
