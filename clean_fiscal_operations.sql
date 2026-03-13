-- ============================================================================
-- Скрипт очистки регистра сведений "ФискальныеОперации" (_InfoRg10981)
-- для 1С 8.x на MS SQL Server
--
-- ВАЖНО: 
--   1) Перед запуском ОБЯЗАТЕЛЬНО выгоните всех пользователей из 1С
--      или заблокируйте начало сеансов в консоли администрирования.
--   2) Сделайте РЕЗЕРВНУЮ КОПИЮ базы данных!
--   3) Модель восстановления рекомендуется SIMPLE на время удаления,
--      либо делайте периодический бэкап лога транзакций между пакетами.
-- ============================================================================

USE [Retail_POBEDA]

SET NOCOUNT ON;

-- ===================== НАСТРОЙКИ =====================

-- Дата в терминах 1С: до какой даты удалять (не включая).
-- 1С хранит даты в SQL со смещением +2000 лет.
-- Пример: 2023-01-01 в 1С = 4023-01-01 в SQL.
--
-- Чтобы удалить всё ДО 1 января 2023 года (в терминах 1С):
DECLARE @CutoffDate1C DATETIME = '4023-01-01 00:00:00';

-- Альтернативный способ: автоматический расчёт.
-- Удалить записи старше 3 лет от текущей даты:
-- DECLARE @CutoffDate1C DATETIME = DATEADD(YEAR, 2000 - 3, GETDATE());

-- Размер пакета: сколько УНИКАЛЬНЫХ регистраторов обрабатывать за одну итерацию.
-- 5000–20000 — оптимально. Не ставьте больше 50000.
DECLARE @BatchSize INT = 10000;

-- Пауза между пакетами в секундах (0 = без пауз).
-- 1-2 секунды — щадящий режим, снижает нагрузку на сервер.
DECLARE @DelaySeconds INT = 1;

-- ===================== КОНЕЦ НАСТРОЕК =====================

DECLARE @RowsAffected INT = 1;
DECLARE @TotalDeletedMain BIGINT = 0;
DECLARE @TotalDeletedChng BIGINT = 0;
DECLARE @DeletedMain INT;
DECLARE @DeletedChng INT;
DECLARE @BatchNum INT = 0;
DECLARE @StartTime DATETIME = GETDATE();
DECLARE @DelayStr VARCHAR(8);

SET @DelayStr = '00:00:' + RIGHT('0' + CAST(@DelaySeconds AS VARCHAR(2)), 2);

-- ===================== ПРЕДВАРИТЕЛЬНАЯ ИНФОРМАЦИЯ =====================

PRINT '============================================================';
PRINT CHAR(13) + CHAR(10);
PRINT '  Очистка регистра ФискальныеОперации (_InfoRg10981)';
PRINT '  База: Retail_POBEDA';
PRINT '  Дата отсечения (SQL): ' + CONVERT(VARCHAR(20), @CutoffDate1C, 120);
PRINT '  Дата отсечения (1С):  ' + CONVERT(VARCHAR(20), DATEADD(YEAR, -2000, @CutoffDate1C), 120);
PRINT '  Размер пакета: ' + CAST(@BatchSize AS VARCHAR(10)) + ' регистраторов';
PRINT '  Пауза между пакетами: ' + CAST(@DelaySeconds AS VARCHAR(5)) + ' сек.';
PRINT '  Старт: ' + CONVERT(VARCHAR(20), @StartTime, 120);
PRINT CHAR(13) + CHAR(10);
PRINT '============================================================';

DECLARE @TotalToDelete BIGINT;
SELECT @TotalToDelete = COUNT_BIG(*)
FROM _InfoRg10981 WITH (NOLOCK)
WHERE _Fld10984 < @CutoffDate1C;

PRINT 'Записей в основной таблице к удалению: ' + CAST(@TotalToDelete AS VARCHAR(20));

DECLARE @TotalChng BIGINT;
SELECT @TotalChng = COUNT_BIG(*)
FROM _InfoRgChngR11005 c WITH (NOLOCK)
INNER JOIN _InfoRg10981 r WITH (NOLOCK) ON c._Fld10982_RRRef = r._Fld10982_RRRef
WHERE r._Fld10984 < @CutoffDate1C;

PRINT 'Записей в таблице изменений к удалению: ' + CAST(@TotalChng AS VARCHAR(20));
PRINT '';

IF @TotalToDelete = 0
BEGIN
    PRINT 'Нет записей для удаления. Выход.';
    RETURN;
END

-- Удаляем временную таблицу если осталась от прошлого запуска
IF OBJECT_ID('tempdb.dbo.#chlist') IS NOT NULL
    DROP TABLE #chlist;

-- ===================== ОСНОВНОЙ ЦИКЛ УДАЛЕНИЯ =====================

WHILE (@RowsAffected > 0)
BEGIN
    SET @BatchNum = @BatchNum + 1;

    -- Собираем пакет УНИКАЛЬНЫХ регистраторов для удаления
    SELECT DISTINCT TOP (@BatchSize) _Fld10982_RRRef
    INTO #chlist
    FROM _InfoRg10981
    WHERE _Fld10984 < @CutoffDate1C;

    SET @RowsAffected = @@ROWCOUNT;

    IF @RowsAffected = 0
    BEGIN
        DROP TABLE #chlist;
        BREAK;
    END

    -- Индекс для быстрого JOIN при удалении
    CREATE CLUSTERED INDEX IX_chlist ON #chlist (_Fld10982_RRRef);

    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1) Удаляем из таблицы регистрации изменений
        DELETE _ir
        FROM _InfoRgChngR11005 _ir
        INNER JOIN #chlist ch ON _ir._Fld10982_RRRef = ch._Fld10982_RRRef;

        SET @DeletedChng = @@ROWCOUNT;

        -- 2) Удаляем из основной таблицы регистра
        DELETE _ir
        FROM _InfoRg10981 _ir
        INNER JOIN #chlist ch ON _ir._Fld10982_RRRef = ch._Fld10982_RRRef;

        SET @DeletedMain = @@ROWCOUNT;

        COMMIT TRANSACTION;

        SET @TotalDeletedMain = @TotalDeletedMain + @DeletedMain;
        SET @TotalDeletedChng = @TotalDeletedChng + @DeletedChng;

        -- Прогресс
        PRINT 'Пакет #' + CAST(@BatchNum AS VARCHAR(10))
            + ' | Основная: -' + CAST(@DeletedMain AS VARCHAR(10))
            + ' (итого: ' + CAST(@TotalDeletedMain AS VARCHAR(20))
            + ' из ' + CAST(@TotalToDelete AS VARCHAR(20))
            + ', ' + CAST(CAST(@TotalDeletedMain * 100.0 / NULLIF(@TotalToDelete, 0) AS DECIMAL(5,1)) AS VARCHAR(10)) + '%)'
            + ' | Изменения: -' + CAST(@DeletedChng AS VARCHAR(10))
            + ' | ' + CONVERT(VARCHAR(20), GETDATE(), 120);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        PRINT '';
        PRINT '*** ОШИБКА в пакете #' + CAST(@BatchNum AS VARCHAR(10)) + ' ***';
        PRINT 'Номер: ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        PRINT 'Сообщение: ' + ERROR_MESSAGE();
        PRINT 'Строка: ' + CAST(ERROR_LINE() AS VARCHAR(10));
        PRINT '';
        PRINT 'Удалено до ошибки: основная=' + CAST(@TotalDeletedMain AS VARCHAR(20))
            + ', изменения=' + CAST(@TotalDeletedChng AS VARCHAR(20));
        PRINT 'Скрипт можно перезапустить — он продолжит с оставшихся записей.';

        DROP TABLE #chlist;
        RETURN;
    END CATCH

    DROP TABLE #chlist;

    -- Пауза между пакетами
    IF @DelaySeconds > 0
        WAITFOR DELAY @DelayStr;
END

-- ===================== ИТОГ =====================

PRINT '';
PRINT '============================================================';
PRINT '  ГОТОВО!';
PRINT '  Удалено из основной таблицы: ' + CAST(@TotalDeletedMain AS VARCHAR(20));
PRINT '  Удалено из таблицы изменений: ' + CAST(@TotalDeletedChng AS VARCHAR(20));
PRINT '  Пакетов выполнено: ' + CAST(@BatchNum AS VARCHAR(10));
PRINT '  Начало: ' + CONVERT(VARCHAR(20), @StartTime, 120);
PRINT '  Окончание: ' + CONVERT(VARCHAR(20), GETDATE(), 120);
PRINT '  Длительность: ' + CAST(DATEDIFF(MINUTE, @StartTime, GETDATE()) AS VARCHAR(10)) + ' мин.';
PRINT '============================================================';
GO


-- ============================================================================
-- ПОСЛЕ УДАЛЕНИЯ (раскомментируйте и выполните отдельно):
-- ============================================================================

/*
USE [Retail_POBEDA]

-- Обновление статистики
UPDATE STATISTICS _InfoRg10981;
UPDATE STATISTICS _InfoRgChngR11005;

-- Перестроение индексов (может занять время)
ALTER INDEX ALL ON _InfoRg10981 REBUILD;
ALTER INDEX ALL ON _InfoRgChngR11005 REBUILD;

-- Сжатие базы (опционально, освобождает место на диске)
-- DBCC SHRINKDATABASE (N'Retail_POBEDA');
*/
