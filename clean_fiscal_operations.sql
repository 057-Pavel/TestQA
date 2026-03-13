-- ============================================================================
-- Очистка регистра "ФискальныеОперации" (_InfoRg10981) по дате
--
-- МЕТОД: копируем нужные записи → TRUNCATE → вставляем обратно.
-- Работает за минуты вместо часов, т.к. TRUNCATE мгновенный,
-- а INSERT с TABLOCK минимально логируется.
--
-- ВАЖНО:
--   1) Выгоните ВСЕХ пользователей из 1С!
--   2) Сделайте РЕЗЕРВНУЮ КОПИЮ базы!
--   3) Убедитесь, что на диске достаточно места для временной копии.
-- ============================================================================

USE [Retail_POBEDA]

SET NOCOUNT ON;

-- ===================== НАСТРОЙКИ =====================

-- Удалить всё ДО этой даты. Формат 1С: +2000 лет.
-- 2023-01-01 в 1С = 4023-01-01 в SQL
DECLARE @CutoffDate1C DATETIME = '4023-01-01 00:00:00';

-- ===================== КОНЕЦ НАСТРОЕК =====================

DECLARE @StartTime DATETIME = GETDATE();
DECLARE @KeepCount BIGINT;
DECLARE @TotalCount BIGINT;

PRINT '============================================================';
PRINT '  Очистка регистра ФискальныеОперации';
PRINT '  Метод: Copy → Truncate → Restore';
PRINT '  Дата отсечения (1С): ' + CONVERT(VARCHAR(10), DATEADD(YEAR, -2000, @CutoffDate1C), 23);
PRINT '  Старт: ' + CONVERT(VARCHAR(20), @StartTime, 120);
PRINT '============================================================';

-- ===== ШАГ 1: Узнаём объёмы =====

SELECT @TotalCount = COUNT_BIG(*) FROM _InfoRg10981 WITH (NOLOCK);
SELECT @KeepCount = COUNT_BIG(*) FROM _InfoRg10981 WITH (NOLOCK) WHERE _Fld10984 >= @CutoffDate1C;

PRINT '';
PRINT 'Всего записей:    ' + CAST(@TotalCount AS VARCHAR(20));
PRINT 'Оставляем (>=):   ' + CAST(@KeepCount AS VARCHAR(20));
PRINT 'Удаляем (<):      ' + CAST(@TotalCount - @KeepCount AS VARCHAR(20));
PRINT '';

IF @KeepCount = @TotalCount
BEGIN
    PRINT 'Нечего удалять — все записи новее даты отсечения.';
    RETURN;
END

-- ===== ШАГ 2: Копируем записи, которые ОСТАВЛЯЕМ =====

PRINT 'Шаг 1/4: Копируем ' + CAST(@KeepCount AS VARCHAR(20)) + ' записей во временную таблицу...';

IF OBJECT_ID('dbo._InfoRg10981_keep', 'U') IS NOT NULL
    DROP TABLE dbo._InfoRg10981_keep;

SELECT *
INTO _InfoRg10981_keep
FROM _InfoRg10981
WHERE _Fld10984 >= @CutoffDate1C;

PRINT '         Скопировано: ' + CAST(@@ROWCOUNT AS VARCHAR(20)) + ' записей.';

-- ===== ШАГ 3: TRUNCATE обеих таблиц (мгновенно) =====

PRINT 'Шаг 2/4: TRUNCATE таблицы изменений (_InfoRgChngR11005)...';
TRUNCATE TABLE _InfoRgChngR11005;
PRINT '         Готово.';

PRINT 'Шаг 3/4: TRUNCATE основной таблицы (_InfoRg10981)...';
TRUNCATE TABLE _InfoRg10981;
PRINT '         Готово.';

-- ===== ШАГ 4: Вставляем обратно с минимальным логированием =====

PRINT 'Шаг 4/4: Вставляем ' + CAST(@KeepCount AS VARCHAR(20)) + ' записей обратно...';

INSERT INTO _InfoRg10981 WITH (TABLOCK)
SELECT * FROM _InfoRg10981_keep;

PRINT '         Вставлено: ' + CAST(@@ROWCOUNT AS VARCHAR(20)) + ' записей.';

-- ===== ШАГ 5: Убираем временную таблицу =====

DROP TABLE _InfoRg10981_keep;

-- ===== ИТОГ =====

PRINT '';
PRINT '============================================================';
PRINT '  ГОТОВО!';
PRINT '  Было:     ' + CAST(@TotalCount AS VARCHAR(20));
PRINT '  Осталось: ' + CAST(@KeepCount AS VARCHAR(20));
PRINT '  Удалено:  ' + CAST(@TotalCount - @KeepCount AS VARCHAR(20));
PRINT '  Время:    ' + CAST(DATEDIFF(SECOND, @StartTime, GETDATE()) AS VARCHAR(10)) + ' сек.';
PRINT '============================================================';
GO


-- ============================================================================
-- Для МАКСИМАЛЬНОЙ скорости INSERT: если модель восстановления FULL,
-- временно переключите на SIMPLE перед запуском:
--
--   ALTER DATABASE [Retail_POBEDA] SET RECOVERY SIMPLE;
--   -- ... запуск скрипта ...
--   ALTER DATABASE [Retail_POBEDA] SET RECOVERY FULL;
--
-- В режиме SIMPLE + TABLOCK вставка будет минимально логироваться.
-- ============================================================================
