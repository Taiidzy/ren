import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  mainSidebar: [
    {
      type: 'doc',
      id: 'intro',
      label: 'Введение',
    },
    {
      type: 'category',
      label: 'Начало работы',
      link: {
        type: 'doc',
        id: 'getting-started/installation',
      },
      items: [
        'getting-started/installation',
        'getting-started/quick-start',
        'getting-started/configuration',
      ],
    },
    {
      type: 'category',
      label: 'Руководства',
      link: {
        type: 'generated-index',
        title: 'Руководства пользователя',
        description: 'Сценарии использования Ren',
      },
      items: [
        'guides/registration',
        'guides/messages',
        'guides/chats',
      ],
    },
    {
      type: 'category',
      label: 'API',
      link: {
        type: 'doc',
        id: 'api/reference',
      },
      items: [
        'api/reference',
      ],
    },
    {
      type: 'category',
      label: 'Архитектура',
      link: {
        type: 'doc',
        id: 'architecture/overview',
      },
      items: [
        'architecture/overview',
      ],
    },
    {
      type: 'category',
      label: 'Развёртывание',
      link: {
        type: 'doc',
        id: 'deployment/index',
      },
      items: [
        'deployment/index',
      ],
    },
    {
      type: 'category',
      label: 'Разработка',
      link: {
        type: 'generated-index',
        title: 'Разработка',
        description: 'Руководства для разработчиков',
      },
      items: [
        'development/contributing',
        'development/testing',
      ],
    },
    {
      type: 'category',
      label: 'Справочник',
      link: {
        type: 'generated-index',
        title: 'Справочник',
        description: 'Дополнительная информация',
      },
      items: [
        'reference/changelog',
        'reference/troubleshooting',
        'reference/faq',
      ],
    },
  ],
};

export default sidebars;
