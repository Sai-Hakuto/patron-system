--[[==========================================================================
  PATRON SYSTEM - DIALOGUE DATA v2.0 (ОБНОВЛЕННАЯ СТРУКТУРА)
  Добавлены: MajorNode, SET_MAJOR_NODE actions, правильная навигация
============================================================================]]

local Dialogues = {
    
    --[[=======================================================================
      ПУСТОТА (PatronID = 1) - Диалоги 10001-19999
    =========================================================================]]
    
    -- === Arc 1: Первая встреча ===
    
    [10001] = { 
        SpeakerID = 1, 
        MajorNode = true,  -- ✅ ИСПРАВЛЕНО: Это точка восстановления
        IsPlayerOption = false, 
        Text = "Ты пришел. Тишина между мирами нарушена твоим шагом. Говори. Чего ты ищешь?", 
        Portrait = "curious", -- Проявляет интерес к пришедшему
        AnswerOptions = {10101, 10102} 
    },
    
    -- Player Options для первой встречи
    [10101] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Я ищу силу, чтобы сокрушать врагов.", 
        NextNodeID = 10002,
        Actions = {
            {Type = "PLAY_SOUND", SoundID = 12513}
        }
    },
    [10102] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Я хочу понять природу тьмы.", 
        NextNodeID = 10003,
        Conditions = {{Type="MIN_LEVEL", Level=5}}, -- Только для 5+ уровня
        Actions = {
            {Type = "PLAY_SOUND", SoundID = 12515}
        }
    },
    
    -- Уникальные ответы Пустоты
    [10002] = { 
        SpeakerID = 1, 
        IsPlayerOption = false, 
        Text = "Сила... предсказуемое желание. Оно будет удовлетворено.", 
        Portrait = "pleased", -- Довольна предсказуемостью
        NextNodeID = 10004 
    },
    [10003] = { 
        SpeakerID = 1, 
        IsPlayerOption = false, 
        Text = "Понимание... редкий запрос. Оно придет через служение.", 
        Portrait = "curious", -- Заинтересована необычным желанием
        NextNodeID = 10004
    },
    
    -- Общий ответ Пустоты (Part 1)
    [10004] = { 
        SpeakerID = 1, 
        IsPlayerOption = false, 
        Text = "Каждая угасшая жизнь оставляет эхо. Каждая душа, поглощенная тобой, станет частью нашего общего... понимания.", 
        Portrait = "threatening", -- Более зловещий тон
        NextNodeID = 10005 
    },
    
    -- Общий ответ Пустоты (Part 2) + финальная опция
    [10005] = { 
        SpeakerID = 1, 
        IsPlayerOption = false, 
        Text = "Принеси мне сто таких отголосков, и я дам тебе первое благословение. Ты согласен на этот обмен?", 
        AnswerOptions = {10103, 10106} -- ✅ ИСПРАВЛЕНО: Два варианта ответа
    },
    
    -- Финальные выборы игрока
    [10103] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Я согласен.", 
        Actions = { 
            {Type="ADD_POINTS", Amount=50, PatronID=1}, 
            {Type="ADD_EVENT", EventName="ACCEPTED_VOID_PACT", PatronID=1},
            {Type="SET_MAJOR_NODE", NodeID=10006, PatronID=1}, -- ✅ НОВОЕ: Переход к Arc 2
            {Type="UNLOCK_BLESSING", BlessingID=1001} -- ✅ НОВОЕ: Разблокировка благословения
        } 
    },
    [10106] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Мне нужно подумать.", 
        Actions = { 
            {Type="ADD_EVENT", EventName="VOID_PACT_DECLINED", PatronID=1} -- Остается на том же MajorNode
        } 
    },
    
    -- === Arc 2: Выполнение пакта ===
    
    [10006] = { 
        SpeakerID = 1, 
        MajorNode = true, -- ✅ НОВОЕ: Вторая точка восстановления
        IsPlayerOption = false, 
        Text = "Ты вернулся. Выполнил ли ты свою часть соглашения?", 
        AnswerOptions = {10104, 10105, 10107} 
    },
    
    [10104] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Да, души собраны. Прими их.", 
        Conditions = {
            {Type="HAS_SOULS", Amount=100},
            {Type="HAS_EVENT", EventName="ACCEPTED_VOID_PACT", PatronID=1}
        },
        Actions = { 
            {Type="LOST_SOULS", Amount=100}, 
            {Type="UNLOCK_BLESSING", BlessingID=1002}, -- Второе благословение
            {Type="ADD_POINTS", Amount=100, PatronID=1},
            {Type="SET_MAJOR_NODE", NodeID=10008, PatronID=1}, -- ✅ НОВОЕ: Переход к Arc 3
            {Type="ADD_EVENT", EventName="VOID_PACT_COMPLETED", PatronID=1}
        } 
    },
    [10105] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Мне нужно больше времени.", 
        NextNodeID = 10007 
    },
    [10107] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Я передумал. Этот пакт мне не нужен.",
        Conditions = {{Type="HAS_EVENT", EventName="ACCEPTED_VOID_PACT", PatronID=1}},
        Actions = {
            {Type="REMOVE_EVENT", EventName="ACCEPTED_VOID_PACT", PatronID=1},
            {Type="ADD_EVENT", EventName="VOID_PACT_BROKEN", PatronID=1},
            {Type="SET_MAJOR_NODE", NodeID=10001, PatronID=1} -- ✅ НОВОЕ: Возврат к началу
        }
    },
    
    -- Ответы для Arc 2
    [10007] = { 
        SpeakerID = 1, 
        IsPlayerOption = false, 
        Text = "Торопись. Пустота не терпит промедления."
    },
    
    -- === Arc 3: Углубление отношений ===
    
    [10008] = { 
        SpeakerID = 1, 
        MajorNode = true, -- ✅ НОВОЕ: Третья точка восстановления
        IsPlayerOption = false, 
        Text = "Ты доказал свою преданность. Готов ли ты к большему служению?", 
        AnswerOptions = {10108, 10109} 
    },
    
    [10108] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Я готов служить Пустоте.", 
        Actions = { 
            {Type="ADD_POINTS", Amount=25, PatronID=1},
            {Type="UNLOCK_FOLLOWER", FollowerID=101}, -- ✅ НОВОЕ: Алайя
            {Type="ADD_EVENT", EventName="DEEP_VOID_SERVICE", PatronID=1}
        } 
    },
    [10109] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Пока я довольствуюсь тем, что имею." 
        -- Остается на том же MajorNode
    },

    --[[=======================================================================
      ДРАКОН ЛОРД (PatronID = 2) - Диалоги 20001-29999
    =========================================================================]]
    
    -- === Arc 1: Первое знакомство ===
    
    [20001] = { 
        SpeakerID = 2, 
        MajorNode = true, -- ✅ НОВОЕ: Начальная точка Дракона
        IsPlayerOption = false, 
        Text = "Добро пожаловать, искатель приключений! Или, как я предпочитаю, 'клиент'. Что привело тебя в мою скромную сокровищницу?", 
        AnswerOptions = {20101, 20102} 
    },
    
    [20101] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Мне нужны редкие артефакты и могущество.", 
        NextNodeID = 20002 
    },
    [20102] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Я ищу знания и мудрые советы.", 
        NextNodeID = 20003 
    },
    
    -- Уникальные ответы Дракона
    [20002] = { 
        SpeakerID = 2, 
        IsPlayerOption = false, 
        Text = "Конечно-конечно! Лучшие товары для лучшего покупателя. У меня всё есть, вопрос лишь в цене.", 
        NextNodeID = 20004 
    },
    [20003] = { 
        SpeakerID = 2, 
        IsPlayerOption = false, 
        Text = "Знания? Хм. Консультации у меня тоже платные, но для тебя сделаем скидку. Первичный приём — бесплатно!", 
        NextNodeID = 20004
    },
    
    -- Общий ответ Дракон Лорда (Part 1)
    [20004] = { 
        SpeakerID = 2, 
        IsPlayerOption = false, 
        Text = "Видишь ли, могущество, как и любой другой товар, имеет свою стоимость. Оно не возникает из ниоткуда. Его нужно... инвестировать.", 
        NextNodeID = 20005 
    },
    
    -- Общий ответ (Part 2) + финальная опция
    [20005] = { 
        SpeakerID = 2, 
        IsPlayerOption = false, 
        Text = "Начнем с малого. Сделай взнос в наш 'фонд процветания' в размере 100 золотых, и я открою тебе доступ к моим базовым услугам. Идет?", 
        AnswerOptions = {20103, 20106} 
    },
    
    [20103] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "[Заплатить 100 золотых] Это хорошая инвестиция.", 
        Conditions = {{Type="HAS_MONEY", Amount=1000000}}, -- 100 золотых в медных монетах
        Actions = { 
            {Type="LOST_MONEY", Amount=1000000}, 
            {Type="UNLOCK_BLESSING", BlessingID=2001}, 
            {Type="ADD_POINTS", Amount=50, PatronID=2},
            {Type="SET_MAJOR_NODE", NodeID=20006, PatronID=2}, -- ✅ НОВОЕ: Переход к Arc 2
            {Type="ADD_EVENT", EventName="DRAGON_INVESTMENT_MADE", PatronID=2}
        } 
    },
    [20106] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "У меня нет таких денег.", 
        NextNodeID = 20007
    },
    
    [20007] = { 
        SpeakerID = 2, 
        IsPlayerOption = false, 
        Text = "Понимаю, понимаю. Возвращайся, когда будешь готов к серьезному бизнесу. Время — деньги!" 
    },
    
    -- === Arc 2: Деловые отношения ===
    
    [20006] = { 
        SpeakerID = 2, 
        MajorNode = true, -- ✅ НОВОЕ: Вторая точка Дракона
        IsPlayerOption = false, 
        Text = "А, мой инвестор! Как дела? Готов к более серьезным предложениям?", 
        AnswerOptions = {20104, 20105} 
    },
    
    [20104] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Расскажи о своих товарах.",
        Actions = { 
            {Type="ADD_EVENT", EventName="BROWSED_DRAGON_SHOP", PatronID=2}
        } 
    },
    [20105] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Хочу увеличить свои инвестиции.", 
        Conditions = {{Type="HAS_MONEY", Amount=5000000}}, -- 500 золотых
        Actions = { 
            {Type="LOST_MONEY", Amount=5000000}, 
            {Type="ADD_POINTS", Amount=100, PatronID=2},
            {Type="SET_MAJOR_NODE", NodeID=20008, PatronID=2}, -- ✅ НОВОЕ: Переход к Arc 3
            {Type="UNLOCK_FOLLOWER", FollowerID=102} -- ✅ НОВОЕ: Арле'Кино
        } 
    },

    --[[=======================================================================
      ЭЛУНА (PatronID = 3) - Диалоги 30001-39999
    =========================================================================]]
    
    -- === Arc 1: Первый контакт ===
    
    [30001] = { 
        SpeakerID = 3, 
        MajorNode = true, -- ✅ НОВОЕ: Начальная точка Элуны
        IsPlayerOption = false, 
        Text = "Ах, вот и ты, моё заблудшее дитя. Я чувствовала твою боль. Мир так жесток к таким чистым душам, не так ли?", 
        AnswerOptions = {30101, 30102} 
    },
    
    [30101] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Да, мир несправедлив. Я хочу это исправить.", 
        NextNodeID = 30002 
    },
    [30102] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Я не уверен, что понимаю, о чем ты.", 
        NextNodeID = 30003 
    },
    
    -- Уникальные ответы Элуны
    [30002] = { 
        SpeakerID = 3, 
        IsPlayerOption = false, 
        Text = "Какое благородство! Я знала, что в тебе есть искра истинного света. Мы накажем тех, кто сеет хаос.", 
        NextNodeID = 30004
    },
    [30003] = { 
        SpeakerID = 3, 
        IsPlayerOption = false, 
        Text = "Милый, не нужно всё понимать. Достаточно просто чувствовать. Чувствовать, что что-то... не так. И довериться мне.", 
        NextNodeID = 30004 
    },
    
    -- Общий ответ Элуны (Part 1)
    [30004] = { 
        SpeakerID = 3, 
        IsPlayerOption = false, 
        Text = "Чтобы бороться с тьмой, иногда нужно самому стать немного... жёстче. Принять на себя бремя, которое сломало бы других.", 
        NextNodeID = 30005 
    },
    
    -- Общий ответ (Part 2) + финальная опция
    [30005] = { 
        SpeakerID = 3, 
        IsPlayerOption = false, 
        Text = "Есть один торговец в Штормграде... он обманывает сирот. Это так ужасно. Прими на себя проклятие немоты, пострадай за них, и я увижу твою решимость. Ты готов к такой жертве?", 
        AnswerOptions = {30103, 30106} 
    },
    
    [30103] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Я готов пострадать во имя справедливости.", 
        Actions = { 
            {Type="APPLY_AURA", AuraSpellID=1853, Duration=60}, -- Silence на 1 минуту
            {Type="ADD_POINTS", Amount=50, PatronID=3}, 
            {Type="SET_MAJOR_NODE", NodeID=30006, PatronID=3}, -- ✅ НОВОЕ: Переход к Arc 2
            {Type="ADD_EVENT", EventName="ACCEPTED_ELUNA_SACRIFICE", PatronID=3}
        } 
    },
    [30106] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Это слишком для меня.", 
        NextNodeID = 30007
    },
    
    [30007] = { 
        SpeakerID = 3, 
        IsPlayerOption = false, 
        Text = "Понимаю, дорогой. Не все готовы к истинной жертве. Возвращайся, когда будешь сильнее духом." 
    },
    
    -- === Arc 2: Углубление манипуляций ===
    
    [30006] = { 
        SpeakerID = 3, 
        MajorNode = true, -- ✅ НОВОЕ: Вторая точка Элуны
        IsPlayerOption = false, 
        Text = "Ты так хорошо перенес испытание... Я горжусь тобой. Готов ли ты к большему служению светлому делу?", 
        AnswerOptions = {30104, 30105} 
    },
    
    [30104] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Что я должен сделать?", 
        NextNodeID = 30008
    },
    [30105] = { 
        SpeakerID = 0, 
        IsPlayerOption = true, 
        Text = "Я готов на большие жертвы.", 
        Conditions = {{Type="HAS_SUFFERING", Amount=50}},
        Actions = { 
            {Type="LOST_SUFFERING", Amount=50}, 
            {Type="UNLOCK_BLESSING", BlessingID=3001},
            {Type="ADD_POINTS", Amount=75, PatronID=3},
            {Type="SET_MAJOR_NODE", NodeID=30009, PatronID=3}, -- ✅ НОВОЕ: Переход к Arc 3
            {Type="UNLOCK_FOLLOWER", FollowerID=103} -- ✅ НОВОЕ: Узан Дул
        } 
    },
    
    [30008] = { 
        SpeakerID = 3, 
        IsPlayerOption = false, 
        Text = "Есть группа бандитов... они причиняют страдания невинным. Собери их боль, принеси мне пятьдесят капель страдания, и я дам тебе силу покарать зло." 
    },

    --[[=========================================================================
      ТЕСТОВЫЕ ДИАЛОГИ С ФОЛЛОВЕРАМИ (ID: 90000+)
    ===========================================================================]]
	
	-- === Arc F1: Первая встреча с Алайей ===

	[40101] = {
		SpeakerID = 101, -- Алайя
		MajorNode = true,
		IsPlayerOption = false,
		Text = "Тьма отдала меня в твои руки... Что ты хочешь от меня?",
		Portrait = "neutral",
		AnswerOptions = {41101, 41102}
	},

	-- Варианты игрока
	[41101] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Я хочу, чтобы ты помогала мне в пути.",
		NextNodeID = 40102
	},
	[41102] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Я ищу ответы. Расскажи о себе.",
		NextNodeID = 40103
	},

	-- Ответы Алайи
	[40102] = {
		SpeakerID = 101,
		IsPlayerOption = false,
		Text = "Помощь... я не знаю, кем быть. Но я постараюсь.",
		Portrait = "unsure",
		NextNodeID = 40104
	},
	[40103] = {
		SpeakerID = 101,
		IsPlayerOption = false,
		Text = "О себе? Я тень, что блуждала века. Теперь я ищу свет, даже если он исходит от тебя.",
		Portrait = "curious",
		NextNodeID = 40104
	},

	-- Завершение первой арки
	[40104] = {
		SpeakerID = 101,
		IsPlayerOption = false,
		Text = "Позволь идти рядом. Может, в этом я найду смысл.",
		AnswerOptions = {41103, 41104}
	},

	[41103] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Я принимаю тебя.",
		Actions = {
			{Type="UNLOCK_FOLLOWER", FollowerID=101},
			{Type="ACTIVATE_FOLLOWER", FollowerID=101},
			{Type="SET_MAJOR_NODE", NodeID=40105, PatronID=1}
		}
	},
	[41104] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Я пока не готов.",
		Actions = {
			{Type="ADD_EVENT", EventName="ALAYA_DECLINED", PatronID=1}
		}
	},

	-- После принятия
	[40105] = {
		SpeakerID = 101,
		IsPlayerOption = false,
		Text = "Я буду рядом. Но помни, я всё ещё учусь быть собой.",
		Portrait = "calm"
	},
	
	-- === Arc F2: Первая встреча с Арле'Кино ===

	[40201] = {
		SpeakerID = 102,
		MajorNode = true,
		IsPlayerOption = false,
		Text = "Ха! Ты выглядишь так, будто тебе нужен компаньон... или беда. Я – Арле'Кино.",
		Portrait = "smirk",
		AnswerOptions = {41201, 41202}
	},

	[41201] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Мне пригодится твоя удача... даже если она дурная.",
		NextNodeID = 40202
	},
	[41202] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Что ты умеешь?",
		NextNodeID = 40203
	},

	[40202] = {
		SpeakerID = 102,
		IsPlayerOption = false,
		Text = "Удача? Ха! Обычно я всё роняю... Но иногда нахожу блестяшки.",
		NextNodeID = 40204
	},
	[40203] = {
		SpeakerID = 102,
		IsPlayerOption = false,
		Text = "Я торговала, пока дракон не сжёг мою лавку. Теперь я ищу новый прилавок – может, твой карман?",
		NextNodeID = 40204
	},

	[40204] = {
		SpeakerID = 102,
		IsPlayerOption = false,
		Text = "Ну что, берёшь меня с собой?",
		AnswerOptions = {41203, 41204}
	},

	[41203] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Да, пошли вместе.",
		Actions = {
			{Type="UNLOCK_FOLLOWER", FollowerID=102},
			{Type="ACTIVATE_FOLLOWER", FollowerID=102},
			{Type="SET_MAJOR_NODE", NodeID=40205, PatronID=2}
		}
	},
	[41204] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Нет, мне не нужны неприятности.",
		Actions = {
			{Type="ADD_EVENT", EventName="ARLEKINO_DECLINED", PatronID=2}
		}
	},

	[40205] = {
		SpeakerID = 102,
		IsPlayerOption = false,
		Text = "Ха! Тогда готовь мешки – я найду тебе сокровища!",
		Portrait = "grin"
	},
	
	-- === Arc F3: Первая встреча с Узан Дулом ===

	[40301] = {
		SpeakerID = 103,
		MajorNode = true,
		IsPlayerOption = false,
		Text = "Ты... тот, кто владеет моей душой? Скажи, зачем я здесь?",
		Portrait = "angry",
		AnswerOptions = {41301, 41302}
	},

	[41301] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Я зову тебя, чтобы сражаться рядом со мной.",
		NextNodeID = 40302
	},
	[41302] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Я хочу помочь тебе обрести свободу.",
		NextNodeID = 40303
	},

	[40302] = {
		SpeakerID = 103,
		IsPlayerOption = false,
		Text = "Сражаться... Хм. Может, в крови врагов я найду ключ к своей свободе.",
		NextNodeID = 40304
	},
	[40303] = {
		SpeakerID = 103,
		IsPlayerOption = false,
		Text = "Свободу? После веков цепей... Возможно, ты не лжёшь.",
		NextNodeID = 40304
	},

	[40304] = {
		SpeakerID = 103,
		IsPlayerOption = false,
		Text = "Решай: будешь ли ты моим тюремщиком или союзником.",
		AnswerOptions = {41303, 41304}
	},

	[41303] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Я стану твоим союзником.",
		Actions = {
			{Type="UNLOCK_FOLLOWER", FollowerID=103},
			{Type="ACTIVATE_FOLLOWER", FollowerID=103},
			{Type="SET_MAJOR_NODE", NodeID=40305, PatronID=3}
		}
	},
	[41304] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Останься пленником. Так безопаснее.",
		Actions = {
			{Type="ADD_EVENT", EventName="UZAN_REJECTED", PatronID=3}
		}
	},

	[40305] = {
		SpeakerID = 103,
		IsPlayerOption = false,
		Text = "Хорошо. Но знай – я слежу за тобой. Если обманешь, я разорву узы сам.",
		Portrait = "threatening"
	},
    
    -- Тестовый диалог: Вмешательство Тень-Воина в диалог с Пустотой
    [90001] = {
        SpeakerID = 1,              -- Пустота
        MajorNode = true,
        Text = "У меня есть особое задание для тебя, смертный.",
        Portrait = "curious",
        AnswerOptions = {90101, 90102}
    },
    
    [90101] = {
        SpeakerID = 0,              -- Игрок
        IsPlayerOption = true,
        Text = "Я готов выслушать.",
        NextNodeID = 90002
    },
    
    [90102] = {
        SpeakerID = 0,              -- Игрок  
        IsPlayerOption = true,
        Text = "Какого рода задание?",
        NextNodeID = 90002
    },
    
    -- Вмешательство фолловера
    [90002] = {
        SpeakerID = 101,            -- Тень-Воин (фолловер Пустоты)
        Text = "Мастер, позвольте мне сопровождать вашего избранника в этой миссии.",
        Portrait = "respectful",    -- Почтительно просит
        NextNodeID = 90003
    },
    
    -- Реакция Пустоты на вмешательство
    [90003] = {
        SpeakerID = 1,              -- Обратно к Пустоте
        Text = "Хм... твоя преданность отмечена, мой слуга.",
        Portrait = "pleased",       -- Довольна преданностью
        AnswerOptions = {90103, 90104}
    },
    
    [90103] = {
        SpeakerID = 0,              -- Игрок
        IsPlayerOption = true,
        Text = "Дополнительная помощь не помешает.",
        NextNodeID = 90004,
        Actions = {
            {Type = "ADD_EVENT", PatronID = 1, EventName = "ACCEPTED_FOLLOWER_HELP"},
            {Type = "PLAY_SOUND", SoundID = 12513}
        }
    },
    
    [90104] = {
        SpeakerID = 0,              -- Игрок
        IsPlayerOption = true,
        Text = "Я справлюсь один.",
        NextNodeID = 90005,
        Actions = {
            {Type = "ADD_EVENT", PatronID = 1, EventName = "REJECTED_FOLLOWER_HELP"},
            {Type = "PLAY_SOUND", SoundID = 12515}
        }
    },
    
    -- Фолловер благодарит за доверие
    [90004] = {
        SpeakerID = 101,            -- Тень-Воин
        Text = "Ваше доверие не будет предано. Я служу до конца.",
        Portrait = "determined",    -- Решительность
        NextNodeID = 90006
    },
    
    -- Фолловер показывает разочарование  
    [90005] = {
        SpeakerID = 101,            -- Тень-Воин
        Text = "Как пожелаете... Но знайте, что я всегда готов к службе.",
        Portrait = "worried",       -- Обеспокоенность
        NextNodeID = 90006
    },
    
    -- Заключительное слово Пустоты
    [90006] = {
        SpeakerID = 1,              -- Пустота
        Text = "Достаточно. Ступайте оба. Задание ждать не будет.",
        Portrait = "threatening",   -- Повелительный тон
        Actions = {
            {Type = "ADD_POINTS", PatronID = 1, Amount = 25},
            {Type = "SET_MAJOR_NODE", PatronID = 1, NodeID = 90001}
        }
    },
	
	    ---------------------------------------------------------------------------
    -- CORE: PRAY / TRADE / FOLLOWERS  (шаблоны-заглушки под кнопки)
    -- Диапазоны соблюдены: 1xxxx (Void), 2xxxx (Dragon), 3xxxx (Eluna)
    ---------------------------------------------------------------------------

    -- ===== ПУСТОТА (PatronID = 1) =====
    [17001] = { -- Pray core (X70001 -> 17001)
        SpeakerID = 1,
        Text = "Пустота слышит шёпот твоей молитвы. (placeholder)",
        Portrait = "curious",
        NextNodeID = 17002
    },
    [17002] = {
        SpeakerID = 1,
        Text = "Твоя молитва принята. Возвращайся позже. (end)",
        Portrait = "pleased"
    },

    [18001] = { -- Trade core (X80001 -> 18001)
        SpeakerID = 1,
        Text = "Обмен… всегда уместен в тишине между мирами. (placeholder)",
        Portrait = "neutral",
        NextNodeID = 18002
    },
    [18002] = {
        SpeakerID = 1,
        Text = "Сделка отложена. Вернёмся к торговле позже. (end)",
        Portrait = "neutral"
    },

    -- === Followers core (Void) === 19001+
	[19001] = {
		SpeakerID = 1,
		MajorNode = true,
		Text = "Ты желаешь спутника из тишины. Позвать ли душу по имени Алайя?",
		Portrait = "curious",
		AnswerOptions = {19101, 19102}
	},

	-- Открыть Алайю
	[19101] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Да. Открой её для меня.",
		Actions = {
			{Type="UNLOCK_FOLLOWER", FollowerID=101},                 -- помечает как обнаруженную/доступную
			{Type="ADD_EVENT", EventName="VOID_FOLLOWER_101_UNLOCKED", PatronID=1},
			{Type="SET_MAJOR_NODE", NodeID=19003, PatronID=1}         -- следующий “состоявшийся” узел
		}
	},

	-- Отложить
	[19102] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Позже. Я ещё не готов.",
		Actions = {
			{Type="ADD_EVENT", EventName="VOID_FOLLOWER_101_POSTPONED", PatronID=1}
			-- MajorNode не меняем, чтобы вернуться снова к 19001
		}
	},

	-- После открытия
	[19003] = {
		SpeakerID = 1,
		Text = "Алайя услышала зов. Она придёт, когда ты её позовёшь.",
		Portrait = "pleased"
	},

    -- ===== ДРАКОН (PatronID = 2) =====
    [27001] = { -- Pray
        SpeakerID = 2,
        Text = "Дракон внемлет. Говори своей молитвой. (placeholder)",
        Portrait = "curious",
        NextNodeID = 27002
    },
    [27002] = {
        SpeakerID = 2,
        Text = "Молитва услышана. Возвращайся, когда пламя окрепнет. (end)",
        Portrait = "pleased"
    },

    [28001] = { -- Trade
        SpeakerID = 2,
        Text = "Сделки закаляют волю. Предмет обсуждения? (placeholder)",
        Portrait = "neutral",
        NextNodeID = 28002
    },
    [28002] = {
        SpeakerID = 2,
        Text = "Торговлю отложим. Подготовь достойное предложение. (end)",
        Portrait = "neutral"
    },

    -- === Followers core (Dragon) === 29001+
	[29001] = {
		SpeakerID = 2,
		MajorNode = true,
		Text = "Спутник тебе нужен? Я верну тебе одну из своих — Арле'Кино. Берёшь?",
		Portrait = "curious",
		AnswerOptions = {29101, 29102}
	},

	[29101] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Да. Открой Арле'Кино.",
		Actions = {
			{Type="UNLOCK_FOLLOWER", FollowerID=102},
			{Type="ADD_EVENT", EventName="DRAGON_FOLLOWER_102_UNLOCKED", PatronID=2},
			{Type="SET_MAJOR_NODE", NodeID=29003, PatronID=2}
		}
	},

	[29102] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Пока воздержусь.",
		Actions = {
			{Type="ADD_EVENT", EventName="DRAGON_FOLLOWER_102_POSTPONED", PatronID=2}
		}
	},

	[29003] = {
		SpeakerID = 2,
		Text = "Ха! Хороший выбор. Её удача странна, но порой щедра.",
		Portrait = "pleased"
	},

    -- ===== ЭЛУНА (PatronID = 3) =====
    [37001] = { -- Pray
        SpeakerID = 3,
        Text = "Элуна склоняет лунный свет к твоей молитве. (placeholder)",
        Portrait = "curious",
        NextNodeID = 37002
    },
    [37002] = {
        SpeakerID = 3,
        Text = "Пусть свет хранит тебя. Возвращайся позже. (end)",
        Portrait = "pleased"
    },

    [38001] = { -- Trade
        SpeakerID = 3,
        Text = "Обмен? Даже звёзды ведут счёт дарам. (placeholder)",
        Portrait = "neutral",
        NextNodeID = 38002
    },
    [38002] = {
        SpeakerID = 3,
        Text = "Пока без сделки. Пусть расчёт будет точным. (end)",
        Portrait = "neutral"
    },

    -- === Followers core (Eluna) === 39001+
	[39001] = {
		SpeakerID = 3,
		MajorNode = true,
		Text = "Ты просишь спутника под лунным светом. Узану Дулу позволить идти рядом?",
		Portrait = "curious",
		AnswerOptions = {39101, 39102}
	},

	[39101] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Да. Открой Узана Дула.",
		Actions = {
			{Type="UNLOCK_FOLLOWER", FollowerID=103},
			{Type="ADD_EVENT", EventName="ELUNA_FOLLOWER_103_UNLOCKED", PatronID=3},
			{Type="SET_MAJOR_NODE", NodeID=39003, PatronID=3}
		}
	},

	[39102] = {
		SpeakerID = 0,
		IsPlayerOption = true,
		Text = "Не сейчас.",
		Actions = {
			{Type="ADD_EVENT", EventName="ELUNA_FOLLOWER_103_POSTPONED", PatronID=3}
		}
	},

	[39003] = {
		SpeakerID = 3,
		Text = "Да будет путь его прям, а выбор — свободен.",
		Portrait = "pleased"
	}

}

return Dialogues



