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
-- 50000 — агрессивный режим, быстрее. Если лог растёт — уменьшите до 10000-20000.
DECLARE @BatchSize INT = 50000;

-- Пауза между пакетами в секундах (0 = без пауз, максимальная скорость).
DECLARE @DelaySeconds INT = 0;

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
PRINT '  Очистка регистра ФискальныеОперации (_InfoRg10981)';
PRINT '  База: Retail_POBEDA';
PRINT '  Дата отсечения (SQL): ' + CONVERT(VARCHAR(20), @CutoffDate1C, 120);
PRINT '  Дата отсечения (1С):  ' + CONVERT(VARCHAR(20), DATEADD(YEAR, -2000, @CutoffDate1C), 120);
PRINT '  Размер пакета: ' + CAST(@BatchSize AS VARCHAR(10)) + ' регистраторов';
PRINT '  Старт: ' + CONVERT(VARCHAR(20), @StartTime, 120);
PRINT '============================================================';
PRINT '';
PRINT 'Подсчёт записей к удалению (основная таблица)...';

DECLARE @TotalToDelete BIGINT;
SELECT @TotalToDelete = COUNT_BIG(*)
FROM _InfoRg10981 WITH (NOLOCK)
WHERE _Fld10984 < @CutoffDate1C;

PRINT 'Записей к удалению: ' + CAST(@TotalToDelete AS VARCHAR(20));
PRINT '';

IF @TotalToDelete = 0
BEGIN
    PRINT 'Нет записей для удаления. Выход.';
    RETURN;
END

IF OBJECT_ID('tempdb.dbo.#chlist') IS NOT NULL
    DROP TABLE #chlist;

-- ===================== ОСНОВНОЙ ЦИКЛ УДАЛЕНИЯ =====================

PRINT 'Начинаю удаление пакетами...';
PRINT '';

WHILE (@RowsAffected > 0)
BEGIN
    SET @BatchNum = @BatchNum + 1;

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

    CREATE CLUSTERED INDEX IX_chlist ON #chlist (_Fld10982_RRRef);

    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DELETE _ir
        FROM _InfoRgChngR11005 _ir
        INNER JOIN #chlist ch ON _ir._Fld10982_RRRef = ch._Fld10982_RRRef;

        SET @DeletedChng = @@ROWCOUNT;

        DELETE _ir
        FROM _InfoRg10981 _ir
        INNER JOIN #chlist ch ON _ir._Fld10982_RRRef = ch._Fld10982_RRRef;

        SET @DeletedMain = @@ROWCOUNT;

        COMMIT TRANSACTION;

        SET @TotalDeletedMain = @TotalDeletedMain + @DeletedMain;
        SET @TotalDeletedChng = @TotalDeletedChng + @DeletedChng;

        RAISERROR('Пакет #%d | Осн: -%d (всего %I64d из %I64d, %d%%) | Изм: -%d | %s',
            0, 1,
            @BatchNum, @DeletedMain, @TotalDeletedMain, @TotalToDelete,
            @TotalDeletedMain * 100 / @TotalToDelete,
            @DeletedChng,
            @StartTime) WITH NOWAIT;

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
        PRINT 'Удалено до ошибки: осн=' + CAST(@TotalDeletedMain AS VARCHAR(20))
            + ', изм=' + CAST(@TotalDeletedChng AS VARCHAR(20));
        PRINT 'Скрипт можно перезапустить — продолжит с оставшихся записей.';

        DROP TABLE #chlist;
        RETURN;
    END CATCH

    DROP TABLE #chlist;

    IF @DelaySeconds > 0
        WAITFOR DELAY @DelayStr;
END

-- ===================== ИТОГ =====================

PRINT '';
PRINT '============================================================';
PRINT '  ГОТОВО!';
PRINT '  Удалено из основной таблицы:  ' + CAST(@TotalDeletedMain AS VARCHAR(20));
PRINT '  Удалено из таблицы изменений: ' + CAST(@TotalDeletedChng AS VARCHAR(20));
PRINT '  Пакетов выполнено: ' + CAST(@BatchNum AS VARCHAR(10));
PRINT '  Начало:      ' + CONVERT(VARCHAR(20), @StartTime, 120);
PRINT '  Окончание:   ' + CONVERT(VARCHAR(20), GETDATE(), 120);
PRINT '  Длительность: ' + CAST(DATEDIFF(MINUTE, @StartTime, GETDATE()) AS VARCHAR(10)) + ' мин.';
PRINT '============================================================';
GO


-- ============================================================================
-- ПОСЛЕ УДАЛЕНИЯ (раскомментируйте и выполните отдельно):
-- ============================================================================

/*
USE [Retail_POBEDA]

UPDATE STATISTICS _InfoRg10981;
UPDATE STATISTICS _InfoRgChngR11005;

ALTER INDEX ALL ON _InfoRg10981 REBUILD;
ALTER INDEX ALL ON _InfoRgChngR11005 REBUILD;

-- DBCC SHRINKDATABASE (N'Retail_POBEDA');
*/
