import assert from 'node:assert/strict'
import test from 'node:test'
import { webConfig } from './config.mjs'

const interfaces = {
  lo: [{ family: 'IPv4', internal: true, address: '127.0.0.1' }],
  eth0: [{ family: 'IPv6', internal: false, address: 'fe80::1' },
    { family: 'IPv4', internal: false, address: '172.20.0.2' }],
}
test('binds the container IPv4 and explicitly trusts the advertised browser authority', () => {
  const config = webConfig({}, interfaces)
  assert.equal(config.host, '172.20.0.2')
  assert.equal(config.port, 3080)
  assert.ok(config.args.includes('--no-open'))
  assert.deepEqual(config.args.slice(-2), ['--trusted-host', 'localhost:3080'])
})
test('supports HTTPS proxy URLs with a prefix and additional browser authorities', () => {
  const config = webConfig({ DSH_WEB_PUBLIC_URL: 'https://agent.example/dsh/',
    DSH_WEB_TRUSTED_HOSTS: 'agent.example, 192.0.2.1:8080', DSH_WEB_PORT: '8080' }, interfaces)
  assert.equal(config.publicUrl.pathname, '/dsh/')
  assert.equal(config.port, 8080)
  assert.deepEqual(config.args.slice(-4), ['--trusted-host', 'agent.example', '--trusted-host', '192.0.2.1:8080'])
})
test('supports an explicit concrete address for host networking', () => {
  assert.equal(webConfig({ DSH_WEB_HOST: '127.0.0.1' }, {}).host, '127.0.0.1')
})
test('fails before launch when no usable interface or an invalid bind address is supplied', () => {
  assert.throws(() => webConfig({}, {}), /concrete local IP/)
  for (const host of ['0.0.0.0', '::', 'example.com']) {
    assert.throws(() => webConfig({ DSH_WEB_HOST: host }, interfaces), /concrete local IP/)
  }
})
test('rejects invalid ports and credential-bearing or non-HTTP browser URLs', () => {
  for (const port of ['0', '65536', '1.5', 'abc']) {
    assert.throws(() => webConfig({ DSH_WEB_PORT: port }, interfaces), /DSH_WEB_PORT/)
  }
  for (const url of ['file:///etc/passwd', 'https://user:pass@example.com/']) {
    assert.throws(() => webConfig({ DSH_WEB_PUBLIC_URL: url }, interfaces), /DSH_WEB_PUBLIC_URL/)
  }
})
