/** An unauthenticated frontend must answer 401 once its auth handler is mounted. */
import http from 'node:http'
import { webConfig } from './config.mjs'

const { host, port, publicUrl } = webConfig()
const request = http.get({ host, port, path: '/', headers: { Host: publicUrl.host }, timeout: 4000 }, response => {
  response.resume()
  process.exitCode = response.statusCode === 401 ? 0 : 1
})
request.on('timeout', () => request.destroy(new Error('Web health check timed out')))
request.on('error', () => { process.exitCode = 1 })
