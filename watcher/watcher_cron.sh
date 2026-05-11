#!/bin/bash

# ------------------------------
# Конфигурация
# ------------------------------
FLASK_URL="http://192.168.25.77:5000"
JENKINS_URL="http://192.168.25.77:8080"          # Замените на реальный адрес Jenkins
JENKINS_JOB_WORKER="Worker-test"
JENKINS_USER="admin"                    # Логин Jenkins
JENKINS_TOKEN="12345678"                  # API Token (создайте в профиле)

# ------------------------------
# Функции
# ------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# проверяем, установлены ли curl и jq
if ! command -v jq &> /dev/null; then
    log "jq не найден. Установите: sudo apt install jq"
    exit 1
fi

# 1. Получаем проекты и зеркало
PROJECTS=$(curl -s "${FLASK_URL}/api/projects")
MIRROR=$(curl -s "${FLASK_URL}/api/mirror_all")

# Строим ассоциативный массив зеркальных записей
declare -A mirror_map
while IFS= read -r row; do
    name=$(echo "$row" | jq -r '.project_name')
    if [ -n "$name" ] && [ "$name" != "null" ]; then
        mirror_map["$name"]="$row"
    fi
done <<< "$(echo "$MIRROR" | jq -c '.[]')"

# Список шагов для сравнения (должен соответствовать API)
STEPS="status_unpacking status_hash status_extensions status_binaries_in_src status_json_src status_json_bin status_svace_ob_build status_svace_ob_analyze status_svacer_ob_analyze status_buildography_analyze status_izb status_SQ"

# 2. Обрабатываем каждый проект
echo "$PROJECTS" | jq -c '.[]' | while read -r proj_json; do
    proj_name=$(echo "$proj_json" | jq -r '.project_name')
    status_work=$(echo "$proj_json" | jq -r '.status_work // "inactive"')
    
    # Проект уже обрабатывается или застрял – пропускаем
    if [ "$status_work" = "active" ] || [ "$status_work" = "stalled" ]; then
        log "Проект $proj_name имеет status_work=$status_work – пропускаем"
        continue
    fi
    
    mirror_json="${mirror_map[$proj_name]}"
    diff_detected=false
    
    # Если в зеркале нет записи – расхождение
    if [ -z "$mirror_json" ] || [ "$mirror_json" = "null" ]; then
        diff_detected=true
        log "Проект $proj_name не найден в зеркале – расхождение"
    else
        # Сравниваем path_to_code и path_to_buildography
        proj_path=$(echo "$proj_json" | jq -r '.path_to_code')
        mirr_path=$(echo "$mirror_json" | jq -r '.path_to_code')
        if [ "$proj_path" != "$mirr_path" ]; then
            diff_detected=true
            log "Проект $proj_name: path_to_code отличается ($proj_path != $mirr_path)"
        fi
        proj_buildo=$(echo "$proj_json" | jq -r '.path_to_buildography')
        mirr_buildo=$(echo "$mirror_json" | jq -r '.path_to_buildography')
        if [ "$proj_buildo" != "$mirr_buildo" ]; then
            diff_detected=true
            log "Проект $proj_name: path_to_buildography отличается"
        fi
        
        # Сравниваем статусы шагов
        for step in $STEPS; do
            proj_status=$(echo "$proj_json" | jq -r ".${step} // \"NOT_STARTED\"")
            mirr_status=$(echo "$mirror_json" | jq -r ".${step} // \"NOT_STARTED\"")
            if [ "$proj_status" != "$mirr_status" ]; then
                diff_detected=true
                log "Проект $proj_name: статус $step отличается ($proj_status vs $mirr_status)"
                break
            fi
        done
    fi
    
    if [ "$diff_detected" = true ]; then
        log "Расхождение для проекта $proj_name. Устанавливаем status_work=active и запускаем воркера."
        
        # Обновляем status_work на active
        curl -s -X POST "${FLASK_URL}/api/update_status_work" \
            -H "Content-Type: application/json" \
            -d "{\"project_name\": \"${proj_name}\", \"status_work\": \"active\"}"
        
        # Формируем задание для воркера
        task_json=$(jq -n \
            --arg name "$proj_name" \
            --arg path "$(echo "$proj_json" | jq -r '.path_to_code')" \
            --arg buildo "$(echo "$proj_json" | jq -r '.path_to_buildography')" \
            '{project_name: $name, path_to_code: $path, path_to_buildography: $buildo}')
        
        # Запускаем воркера через Jenkins API
        curl -X POST "${JENKINS_URL}/job/${JENKINS_JOB_WORKER}/buildWithParameters" \
            --user "${JENKINS_USER}:${JENKINS_TOKEN}" \
            --data-urlencode "TASK_JSON=${task_json}"
    else
        log "Проект $proj_name: расхождений нет."
    fi
done

log "Вотчер завершил работу."
