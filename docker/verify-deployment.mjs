/** Reject deployment links that would break when only /out enters the final image. */
import { readdirSync, realpathSync, lstatSync } from 'node:fs'
import { join, resolve, sep } from 'node:path'

const root = realpathSync(resolve(process.argv[2]))
function inspect(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name)
    if (entry.isSymbolicLink()) {
      const target = realpathSync(path)
      if (target !== root && !target.startsWith(root + sep)) {
        throw new Error(`Deployment link escapes its image directory: ${path} -> ${target}`)
      }
    } else if (entry.isDirectory()) inspect(path)
  }
}
if (!lstatSync(join(root, 'lib/bin.js')).isFile()) throw new Error('Built dsh CLI is missing')
inspect(root)
console.log('Production deployment contains the built CLI and self-contained links.')
