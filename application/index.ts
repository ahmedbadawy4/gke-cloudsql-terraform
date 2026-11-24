import express from 'express'
import winston from 'winston'
import expressWinston from 'express-winston'

const app = express()
const PORT = Number(process.env.PORT) || 3000
const HEALTH_PATHS = ['/healthz', '/readyz']

let shuttingDown = false

app.disable('x-powered-by')

app.use(
    expressWinston.logger({
        transports: [new winston.transports.Console()],
        meta: false,
        msg: 'HTTP  ',
        expressFormat: true,
        colorize: false,
        // Probe requests every few seconds would drown the real traffic.
        ignoreRoute: (req) => HEALTH_PATHS.includes(req.path)
    })
)

// Liveness: the process is up and can answer.
app.get('/healthz', (req, res) => {
    res.status(200).json({ status: 'ok' })
})

// Readiness: fails during shutdown so the pod leaves the Service first.
app.get('/readyz', (req, res) => {
    if (shuttingDown) {
        res.status(503).json({ status: 'shutting down' })
        return
    }
    res.status(200).json({ status: 'ready' })
})

app.get('/', (req, res) => {
    res.send('The application is running.')
})

app.get('/users/:userId', (req, res) => {
    res.json(req.params)
})

app.use((req, res) => {
    res.status(404).json({ error: 'not found' })
})

const server = app.listen(PORT, () => {
    console.log(`Express server is listening at ${PORT}`)
})

// Kubernetes sends SIGTERM when it stops a pod. Finish open requests, then exit.
process.on('SIGTERM', () => {
    shuttingDown = true
    server.close(() => {
        process.exit(0)
    })
})
