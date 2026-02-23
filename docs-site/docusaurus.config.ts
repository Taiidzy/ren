import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'Ren',
  tagline: 'Безопасный мессенджер с E2EE шифрованием',
  favicon: 'img/favicon.ico',

  future: {
    v4: true,
  },

  // Production URL - replace with actual domain
  url: 'https://ren-messenger.com',
  baseUrl: '/',

  // GitHub pages config - replace with actual repo
  organizationName: 'taiidzy',
  projectName: 'ren',

  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },

  i18n: {
    defaultLocale: 'ru',
    locales: ['ru'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          editUrl: 'https://github.com/taiidzy/ren/tree/main/docs-site/',
          routeBasePath: 'docs',
        },
        blog: false, // Disable blog for now
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    image: 'img/social-card.jpg',
    colorMode: {
      respectPrefersColorScheme: true,
      defaultMode: 'light',
      disableSwitch: false,
    },
    navbar: {
      title: 'Ren',
      logo: {
        alt: 'Ren Logo',
        src: 'img/logo.svg',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'mainSidebar',
          position: 'left',
          label: 'Документация',
        },
        {
          href: 'https://github.com/taiidzy/ren',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Документация',
          items: [
            {
              label: 'Введение',
              to: '/docs/intro',
            },
            {
              label: 'Быстрый старт',
              to: '/docs/getting-started/quick-start',
            },
            {
              label: 'API Reference',
              to: '/docs/api/reference',
            },
          ],
        },
        {
          title: 'Разработка',
          items: [
            {
              label: 'Вклад в проект',
              to: '/docs/development/contributing',
            },
            {
              label: 'Тестирование',
              to: '/docs/development/testing',
            },
            {
              label: 'Changelog',
              to: '/docs/reference/changelog',
            },
          ],
        },
        {
          title: 'Сообщество',
          items: [
            {
              label: 'GitHub',
              href: 'https://github.com/taiidzy/ren',
            },
            {
              label: 'Issues',
              href: 'https://github.com/taiidzy/ren/issues',
            },
            {
              label: 'Email',
              href: 'mailto:taiidzy@yandex.ru',
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Ren Messenger. Apache 2.0 License.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['rust', 'dart', 'bash', 'json', 'typescript', 'sql'],
    },
    docs: {
      sidebar: {
        hideable: true,
        autoCollapseCategories: true,
      },
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
