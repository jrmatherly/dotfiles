/**
 * @see https://prettier.io/docs/en/options
 * @type {import("prettier").Config}
 */
const config = {
  singleQuote: true,
  semi: false,
  trailingComma: 'es5',
  plugins: ['prettier-plugin-sh'],
  overrides: [
    {
      files: '*.md',
      options: {
        arrowParens: 'avoid',
        printWidth: 70,
        proseWrap: 'never',
        trailingComma: 'none',
      },
    },
    // vscode/User/ has its own .prettierrc.yaml (see there for why)
    // JSON with comments: VS Code's jsonc mode flags trailing commas (the
    // fastfetch config accepts them, but the editor shows a warning per comma)
    {
      files: '*.jsonc',
      options: {
        trailingComma: 'none',
      },
    },
    {
      files: 'firefox/user.js',
      options: {
        semi: true,
      },
    },
  ],
}

module.exports = config
