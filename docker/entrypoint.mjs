/** Replace this launcher with the supported CLI so SIGTERM reaches the app. */
import { webConfig } from './config.mjs'

const { args } = webConfig()
process.execve(process.execPath, [process.execPath, '/app/lib/bin.js', ...args, ...process.argv.slice(2)], process.env)
