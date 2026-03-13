-- ============================================================================
-- Скрипт очистки регистра сведений "ФискальныеОперации" (_InfoRg10981)
-- для 1С на MS SQL Server
--
-- ВАЖНО: 
--   1) Перед запуском ОБЯЗАТЕЛЬНО выгоните всех пользователей из 1С
--      или заблокируйте начало сеансов в консоли администрирования.
--   2) Сделайте резервную копию базы данных!
--   3) Модель восстановления рекомендуется SIMPLE на время удаления,
--      либо делайте периодический бэкап лога транзакций.
-- ============================================================================

-- ===================== НАСТРОЙКИ =====================

-- Укажите дату, ДО которой (не включая) нужно удалить записи.
-- Формат: 'YYYYMMDD' (год-месяц-день без разделителей, стандарт 1С в SQL).
-- Все записи, где _Fld10984 < @CutoffDate, будут удалены.
--
-- Пример: удалить всё ДО 1 января 2025 года:
DECLARE @CutoffDate DATETIME = '20250101';

-- Размер пакета удаления (количество строк за одну итерацию).
-- 5000–10000 — хороший компромисс между скоростью и нагрузкой.
-- Если лог транзакций растёт слишком быстро — уменьшите.
-- Если удаление идёт медленно — увеличьте (до 50000 максимум).
DECLARE @BatchSize INT = 5000;

-- Пауза между пакетами в секундах (снижает нагрузку на сервер).
-- 0 = без пауз, 1-2 = щадящий режим для продакшена.
DECLARE @DelaySeconds INT = 1;

-- ===================== КОНЕЦ НАСТРОЕК =====================

SET NOCOUNT ON;

DECLARE @RowsDeleted INT = 1;
DECLARE @TotalDeleted BIGINT = 0;
DECLARE @StartTime DATETIME = GETDATE();
DECLARE @DelayStr VARCHAR(8);
DECLARE @TotalToDelete BIGINT;

-- Формируем строку задержки в формате HH:MM:SS
SET @DelayStr = '00:00:' + RIGHT('0' + CAST(@DelaySeconds AS VARCHAR(2)), 2);

-- ===================== ПРЕДВАРИТЕЛЬНАЯ ИНФОРМАЦИЯ =====================

PRINT '============================================================';
PRINT 'Очистка регистра ФискальныеОперации (_InfoRg10981)';
PRINT 'Дата отсечения (удалить ДО): ' + CONVERT(VARCHAR(20), @CutoffDate, 120);
PRINT 'Размер пакета: ' + CAST(@BatchSize AS VARCHAR(10));
PRINT 'Пауза между пакетами: ' + CAST(@DelaySeconds AS VARCHAR(5)) + ' сек.';
PRINT 'Начало: ' + CONVERT(VARCHAR(20), @StartTime, 120);
PRINT '============================================================';

-- Считаем сколько записей предстоит удалить
SELECT @TotalToDelete = COUNT_BIG(*)
FROM _InfoRg10981 WITH (NOLOCK)
WHERE _Fld10984 < @CutoffDate;

PRINT 'Записей к удалению: ' + CAST(@TotalToDelete AS VARCHAR(20));
PRINT '';

IF @TotalToDelete = 0
BEGIN
    PRINT 'Нет записей для удаления. Выход.';
    RETURN;
END

-- ===================== ОСНОВНОЙ ЦИКЛ УДАЛЕНИЯ =====================

WHILE @RowsDeleted > 0
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE TOP (@BatchSize)
        FROM _InfoRg10981
        WHERE _Fld10984 < @CutoffDate;

        SET @RowsDeleted = @@ROWCOUNT;
        SET @TotalDeleted = @TotalDeleted + @RowsDeleted;

        COMMIT TRANSACTION;

        -- Прогресс
        IF @RowsDeleted > 0
        BEGIN
            PRINT 'Удалено пакетом: ' + CAST(@RowsDeleted AS VARCHAR(10))
                + ' | Всего удалено: ' + CAST(@TotalDeleted AS VARCHAR(20))
                + ' из ' + CAST(@TotalToDelete AS VARCHAR(20))
                + ' (' + CAST(CAST(@TotalDeleted * 100.0 / @TotalToDelete AS DECIMAL(5,1)) AS VARCHAR(10)) + '%)'
                + ' | Время: ' + CONVERT(VARCHAR(20), GETDATE(), 120);
        END

        -- Пауза между пакетами (если задана)
        IF @RowsDeleted > 0 AND @DelaySeconds > 0
            WAITFOR DELAY @DelayStr;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        PRINT '*** ОШИБКА ***';
        PRINT 'Номер: ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        PRINT 'Сообщение: ' + ERROR_MESSAGE();
        PRINT 'Строка: ' + CAST(ERROR_LINE() AS VARCHAR(10));
        PRINT 'Всего удалено до ошибки: ' + CAST(@TotalDeleted AS VARCHAR(20));
        PRINT 'Скрипт можно перезапустить — он продолжит с того же места.';
        RETURN;
    END CATCH
END

-- ===================== ИТОГ =====================

PRINT '';
PRINT '============================================================';
PRINT 'ГОТОВО!';
PRINT 'Всего удалено записей: ' + CAST(@TotalDeleted AS VARCHAR(20));
PRINT 'Начало: ' + CONVERT(VARCHAR(20), @StartTime, 120);
PRINT 'Окончание: ' + CONVERT(VARCHAR(20), GETDATE(), 120);
PRINT 'Длительность: ' + CAST(DATEDIFF(MINUTE, @StartTime, GETDATE()) AS VARCHAR(10)) + ' мин.';
PRINT '============================================================';
GO


-- ============================================================================
-- ДОПОЛНИТЕЛЬНО: Очистка таблицы изменений (_InfoRgChngR11005)
-- Эта таблица хранит записи обмена/регистрации изменений регистра.
-- Если обмен данными НЕ используется — можно очистить полностью.
-- Если обмен ИСПОЛЬЗУЕТСЯ — пропустите этот блок!
-- ============================================================================

/*
-- Раскомментируйте блок ниже, если нужно очистить таблицу изменений.
-- ВНИМАНИЕ: делайте это ТОЛЬКО если понимаете, что таблица изменений
-- вам не нужна (нет обменов, использующих этот регистр).

DECLARE @RowsDeleted2 INT = 1;
DECLARE @TotalDeleted2 BIGINT = 0;
DECLARE @BatchSize2 INT = 10000;

PRINT '';
PRINT 'Очистка таблицы изменений _InfoRgChngR11005...';

WHILE @RowsDeleted2 > 0
BEGIN
    DELETE TOP (@BatchSize2) FROM _InfoRgChngR11005;
    SET @RowsDeleted2 = @@ROWCOUNT;
    SET @TotalDeleted2 = @TotalDeleted2 + @RowsDeleted2;
    
    IF @RowsDeleted2 > 0
        PRINT 'Удалено из таблицы изменений: ' + CAST(@TotalDeleted2 AS VARCHAR(20));
END

PRINT 'Таблица изменений очищена. Удалено: ' + CAST(@TotalDeleted2 AS VARCHAR(20));
*/


-- ============================================================================
-- ПОСЛЕ УДАЛЕНИЯ: рекомендуется выполнить перестроение индексов и обновление
-- статистики для таблицы, чтобы запросы работали оптимально.
-- ============================================================================

/*
-- Раскомментируйте после завершения удаления:

-- Обновление статистики
UPDATE STATISTICS _InfoRg10981;

-- Перестроение всех индексов таблицы (может занять время)
ALTER INDEX ALL ON _InfoRg10981 REBUILD;

-- Сжатие базы данных (освобождение места, опционально)
-- DBCC SHRINKDATABASE (N'ИмяВашейБазы');
*/
