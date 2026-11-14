const {themes: prismThemes} = require('prism-react-renderer');

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Ode Help',
  tagline: 'Help articles for Ode.',
  url: 'https://odebrowser.com',
  baseUrl: '/guides/',
  trailingSlash: true,
  onBrokenLinks: 'throw',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },
  plugins: [require.resolve('./plugins/help-search-index')],
  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: require.resolve('./sidebars.js'),
          breadcrumbs: true,
          showLastUpdateAuthor: false,
          showLastUpdateTime: false,
        },
        blog: false,
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
        sitemap: {
          changefreq: 'weekly',
          priority: 0.7,
        },
      },
    ],
  ],
  themeConfig: {
    metadata: [
      {
        name: 'description',
        content: 'Help articles for Ode for Mac.',
      },
    ],
    colorMode: {
      defaultMode: 'light',
      disableSwitch: true,
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'Ode Help',
      items: [
        {type: 'docSidebar', sidebarId: 'helpSidebar', position: 'left', label: 'Articles'},
        {to: '/keyboard-shortcuts/', label: 'Shortcuts', position: 'left'},
        {to: '/extension-api-compatibility/', label: 'Compatibility', position: 'left'},
        {href: 'https://odebrowser.com/download', label: 'Download for Mac', position: 'right'},
        {href: 'mailto:feedback@odebrowser.com', label: 'Feedback', position: 'right'},
        {href: 'https://odebrowser.com/', label: 'Product site', position: 'right'},
      ],
    },
    docs: {
      sidebar: {
        hideable: true,
        autoCollapseCategories: false,
      },
    },
    footer: {
      style: 'light',
      links: [
        {
          title: 'Ode',
          items: [
            {label: 'Product site', href: 'https://odebrowser.com/'},
            {label: 'Download for Mac', href: 'https://odebrowser.com/download'},
            {label: 'Privacy controls', href: 'https://odebrowser.com/guides/clear-website-data/'},
          ],
        },
        {
          title: 'Help',
          items: [
            {label: 'All articles', to: '/'},
            {label: 'Keyboard shortcuts', to: '/keyboard-shortcuts/'},
            {label: 'Split View', to: '/split-view/'},
            {label: 'Extension compatibility', to: '/extension-api-compatibility/'},
            {label: 'Feedback', href: 'mailto:feedback@odebrowser.com'},
          ],
        },
      ],
      copyright: 'Ode is not affiliated with Arc.',
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  },
};

module.exports = config;
