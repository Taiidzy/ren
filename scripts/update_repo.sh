#!/bin/bash

# Папка проекта (где лежит .git)
PROJECT_DIR="../"  # корень ren

# Перейти в корень проекта
cd "$PROJECT_DIR" || { echo "Папка $PROJECT_DIR не найдена"; exit 1; }

# Обновляем все ветки
git fetch --all --prune

# Показать новые коммиты относительно локальных веток
echo "Новые коммиты в удалённых ветках:"
git log --oneline --branches='*' --not --remotes=origin | head -n 20

# Показать список всех удалённых веток
echo -e "\nДоступные ветки:"
git branch -r

# Выбор ветки
read -p "Введите ветку, которую хотите обновить (например origin/main): " SELECTED_BRANCH

# Создаём временную локальную ветку для выбранной ветки
git checkout -B temp_branch "$SELECTED_BRANCH"

# Показать последние коммиты на выбранной ветке
echo -e "\nКоммиты на $SELECTED_BRANCH:"
git log --oneline -n 10

# Выбор коммита
read -p "Введите хеш коммита для обновления (или оставьте пустым для последнего): " COMMIT_HASH

if [ -n "$COMMIT_HASH" ]; then
    git checkout "$COMMIT_HASH"
fi

echo "Обновление завершено. Перезапуск backend..."

# Перезапуск контейнера backend через docker-compose
docker-compose restart backend

echo "Готово!"