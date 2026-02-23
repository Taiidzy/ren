import type {ReactNode} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';

import styles from './index.module.css';

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className="container">
        <h1 className="hero__title">{siteConfig.title}</h1>
        <p className="hero__subtitle">{siteConfig.tagline}</p>
        <div className={styles.buttons}>
          <Link
            className="button button--secondary button--lg"
            to="/docs/intro">
            Начать работу
          </Link>
          <Link
            className="button button--outline button--secondary button--lg margin-left--md"
            to="https://github.com/taiidzy/ren"
            target="_blank">
            GitHub
          </Link>
        </div>
      </div>
    </header>
  );
}

function HomepageFeaturesSection() {
  const features = [
    {
      title: '🔒 E2EE шифрование',
      description: (
        <>
          Все сообщения шифруются на устройстве отправителя и расшифровываются
          только на устройстве получателя. Сервер не имеет доступа к содержимому.
        </>
      ),
    },
    {
      title: '🌐 Кроссплатформенность',
      description: (
        <>
          Flutter для iOS и Android, React для веба, Rust SDK для всех платформ.
          Единая кодовая база для максимальной производительности.
        </>
      ),
    },
    {
      title: '⚡ Производительность',
      description: (
        <>
          Axum сервер на Rust, PostgreSQL, Tokio runtime. Оптимизированный SDK
          с LTO для минимального размера бинарников.
        </>
      ),
    },
    {
      title: '📁 Обмен файлами',
      description: (
        <>
          Зашифрованная загрузка файлов до 50MB. Потоковая загрузка, поддержка
          chunked файлов, кэширование с ETag.
        </>
      ),
    },
    {
      title: '👥 Группы и каналы',
      description: (
        <>
          Ролевая модель (member/admin/owner). Управление участниками.
          Real-time события через WebSocket.
        </>
      ),
    },
    {
      title: '🔐 Восстановление доступа',
      description: (
        <>
          12-словные мнемонические фразы BIP39 (128 бит энтропии).
          Argon2id memory-hard KDF для максимальной защиты.
        </>
      ),
    },
  ];

  return (
    <section className={styles.features}>
      <div className="container">
        <h2 className={clsx('margin-bottom--lg', 'text--center')}>
          Ключевые возможности
        </h2>
        <div className="row">
          {features.map((props, idx) => (
            <div key={idx} className={clsx('col col--4', 'margin-bottom--md')}>
              <div className={clsx('card', styles.featureCard)}>
                <div className="card__body">
                  <h3>{props.title}</h3>
                  <p>{props.description}</p>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

export default function Home(): ReactNode {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout
      title={siteConfig.tagline}
      description="Документация Ren — современного кроссплатформенного мессенджера со сквозным шифрованием">
      <HomepageHeader />
      <main>
        <HomepageFeaturesSection />
      </main>
    </Layout>
  );
}
