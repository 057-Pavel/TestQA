#language: ru

@tree

Функционал: Создание Номенклатуры

Контекст:
	Дано Я открыл новый сеанс TestClient или подключил уже существующий

Сценарий: Создание в цикле Номенклатуры 
	И Я запоминаю значение выражения '0' в переменную "НомерНоменклатуры" 
	И я делаю 10 раз		
		И Я запоминаю значение выражения '$НомерНоменклатуры$ + 1' в переменную "НомерНоменклатуры"
		И Я запоминаю значение выражения '"Наименование" + $НомерНоменклатуры$' в переменную "Имя"
		Когда Я программно создаю элемент справочника "Items" с реквизитами:
			| 'Description_en' | '$Имя$'   |
			| 'Description_ru' | '$Имя$'   |	
		
		
		
		
		