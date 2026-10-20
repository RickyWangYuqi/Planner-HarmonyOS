// CLI 1.3.4 在关闭遥测时仍创建日志；只将该已核实的日志目录映射进工程。
// 不改变 HOME、LOCALAPPDATA、SDK、用户证书或其余文件访问。
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { syncBuiltinESMExports } = require('node:module');
const destination = process.env.PLANER_CLI_LOG_DIRECTORY;
if (destination) {
  const localDirectory = process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local');
  const original = path.resolve(localDirectory, 'devecocli-mcp-server', 'logs');
  const redirect = (value) => {
    if (typeof value !== 'string') return value;
    const relative = path.relative(original, path.resolve(value));
    if (relative === '' || (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative))) {
      return path.join(destination, relative);
    }
    return value;
  };
  for (const name of ['existsSync', 'mkdirSync', 'readdirSync', 'openSync', 'statSync', 'accessSync', 'unlinkSync']) {
    const operation = fs[name];
    fs[name] = (filePath, ...args) => operation.call(fs, redirect(filePath), ...args);
  }
  const rename = fs.renameSync;
  fs.renameSync = (source, target) => rename.call(fs, redirect(source), redirect(target));
  syncBuiltinESMExports();
}
