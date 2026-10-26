/** Resolve the container listener and browser authority without wildcard binding. */
import { isIP } from 'node:net'
import { networkInterfaces } from 'node:os'

/** Build CLI arguments from deployment settings and concrete network interfaces. */
export function webConfig(env = process.env, interfaces = networkInterfaces()) {
  const host = env.DSH_WEB_HOST || Object.values(interfaces).flat()
    .find(address => address?.family === 'IPv4' && !address.internal)?.address
  if (!host || !isIP(host) || host === '0.0.0.0' || host === '::') {
    throw new Error('DSH_WEB_HOST must be a concrete local IP; no container IPv4 was detected.')
  }
  const portText = env.DSH_WEB_PORT || '3080'
  const port = Number(portText)
  if (!/^\d+$/.test(portText) || !Number.isSafeInteger(port) || port < 1 || port > 65535) {
    throw new Error('DSH_WEB_PORT must be an integer between 1 and 65535.')
  }
  const publicUrl = new URL(env.DSH_WEB_PUBLIC_URL || `http://localhost:${port}/`)
  if (!['http:', 'https:'].includes(publicUrl.protocol) || publicUrl.username || publicUrl.password) {
    throw new Error('DSH_WEB_PUBLIC_URL must be an HTTP(S) URL without credentials.')
  }
  const trustedHosts = new Set([publicUrl.host, ...(env.DSH_WEB_TRUSTED_HOSTS || '')
    .split(',').map(value => value.trim()).filter(Boolean)])
  const args = ['--profile', 'web', '--no-open', '--host', host, '--port', String(port),
    '--public-url', publicUrl.href]
  for (const authority of trustedHosts) args.push('--trusted-host', authority)
  return { host, port, publicUrl, args }
}
