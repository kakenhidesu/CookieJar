import Foundation

enum EmoticonGroup: String, Codable, CaseIterable {
    case official = "X岛颜文字"
    case blueIsland = "蓝岛颜文字"
    case custom = "自定义"
}

enum EmoticonData {

    static let official: [Emoticon] = [
        e("|∀ﾟ"), e("(´ﾟДﾟ`)"), e("(;´Д`)"), e("(｀･ω･)"), e("(=ﾟωﾟ)="),
        e("| ω・´)"), e("|-` )"), e("|д` )"), e("|ー` )"), e("|∀` )"),
        e("(つд⊂)"), e("(ﾟДﾟ≡ﾟДﾟ)"), e("(＾o＾)ﾉ"), e("(|||ﾟДﾟ)"), e("( ﾟ∀ﾟ)"),
        e("( ´∀`)"), e("(*´∀`)"), e("(*ﾟ∇ﾟ)"), e("(*ﾟーﾟ)"), e("(　ﾟ 3ﾟ)"),
        e("( ´ー`)"), e("( ・_ゝ・)"), e("( ´_ゝ`)"), e("(*´д`)"), e("(・ー・)"),
        e("(・∀・)"), e("(ゝ∀･)"), e("(〃∀〃)"), e("(*ﾟ∀ﾟ*)"), e("( ﾟ∀。)"),
        e("( `д´)"), e("(`ε´ )"), e("(`ヮ´ )"), e("σ`∀´)"), e(" ﾟ∀ﾟ)σ"),
        e("ﾟ ∀ﾟ)ノ"), e("(╬ﾟдﾟ)"), e("(|||ﾟдﾟ)"), e("( ﾟдﾟ)"), e("Σ( ﾟдﾟ)"),
        e("( ;ﾟдﾟ)"), e("( ;´д`)"), e("(　д ) ﾟ ﾟ"), e("( ☉д⊙)"), e("(((　ﾟдﾟ)))"),
        e("( ` ・´)"), e("( ´д`)"), e("( -д-)"), e("(>д<)"), e("･ﾟ( ﾉд`ﾟ)"),
        e("( TдT)"), e("(￣∇￣)"), e("(￣3￣)"), e("(￣ｰ￣)"), e("(￣ . ￣)"),
        e("(￣皿￣)"), e("(￣艸￣)"), e("(￣︿￣)"), e("(￣︶￣)"), e("ヾ(´ωﾟ｀)"),
        e("(*´ω`*)"), e("(・ω・)"), e("( ´・ω)"), e("(｀・ω)"), e("(´・ω・`)"),
        e("(`・ω・´)"), e("( `_っ´)"), e("( `ー´)"), e("( ´_っ`)"), e("( ´ρ`)"),
        e("( ﾟωﾟ)"), e("(oﾟωﾟo)"), e("(　^ω^)"), e("(｡◕∀◕｡)"), e("/( ◕‿‿◕ )\\"),
        e("ヾ(´ε`ヾ)"), e("(ノﾟ∀ﾟ)ノ"), e("(σﾟдﾟ)σ"), e("(σﾟ∀ﾟ)σ"), e("|дﾟ )"),
        e("┃電柱┃"), e("ﾟ(つд`ﾟ)"), e("ﾟÅﾟ )　"), e("⊂彡☆))д`)"), e("⊂彡☆))д´)"),
        e("⊂彡☆))∀`)"), e("(´∀((☆ミつ"), e("･ﾟ( ﾉヮ´ )"), e("(ﾉ)`ω´(ヾ)"), e("ᕕ( ᐛ )ᕗ"),
        e("(　ˇωˇ)"), e("( ｣ﾟДﾟ)｣＜"), e("( ›´ω`‹ )"), e("(;´ヮ`)7"), e("(`ゥ´ )"),
        e("(`ᝫ´ )"), e("( ᑭ`д´)ᓀ))д´)ᑫ"), e("σ( ᑒ )"),
        Emoticon(name: "齐齐蛤尔", text: "(`ヮ´ )σ`∀´) ﾟ∀ﾟ)σ", group: .official),
        Emoticon(name: "大嘘", text: """
        吁~~~~　　rnm，退钱！
         　　　/　　　/
        (　ﾟ 3ﾟ) `ー´) `д´) `д´)
        """, group: .official),
        Emoticon(name: "防剧透", text: "[h] [/h]", group: .official),
        Emoticon(name: "骰子", text: "[n]", group: .official),
        Emoticon(name: "高级骰子", text: "[n,m]", group: .official),
    ]

    // Additions and text art follow X岛-EX 4.3.0 (WTFPL):
    // https://github.com/SayaGoodBye/nmbxd-EX/blob/main/nmbxd-EX.user.js
    static let blueIsland: [Emoticon] = [
        b("･ﾟ( ﾉヮ´ )"), b("( ´_ゝ`)旦"), b("(<ゝω・) ☆"), b("(`ε´ (つ*⊂)"),
        b("↙(`ヮ´ )↗ 开摆！"), b("(っ˘Д˘)ノ<"), b("(ﾉ#)`д´)σ"), b("₍₍(ง`ᝫ´ )ว⁾"),
        b("( `ᵂ´)"), b("( *・ω・)✄╰ひ╯"), b("U•ェ•*U"), b("⊂( ﾟωﾟ)つ"),
        b("( ﾟ∀。)7"), b("･ﾟ( ﾟ∀。) ﾟ。"), b("( `д´)σ"), b("( ﾟᯅ 。)"),
        b("( ;`д´; )"), b("m9( `д´)"), b("( ﾟπ。)"), b("ᕕ( ﾟ∀。)ᕗ"),
        b("ฅ(^ω^ฅ)"), b("(|||^ヮ^)"), b("(|||ˇヮˇ)"), b("(　↺ω↺)"),
        b(" `ー´) `д´) `д´)"), b("接☆龙☆大☆成☆功"), b("ᑭ`д´)ᓀ ∑ᑭ(`ヮ´ )ᑫ"),
        b("乚 (^ω^ ﾐэ)Э好钩我咬"), b("乚(`ヮ´  ﾐэ)Э"), b("( ﾟ∀。ﾐэ)Э三三三三　乚"),
        b("(ˇωˇ ﾐэ)Э三三三三　乚"), b("( へ ﾟ∀ﾟ)べ摔低低"), b("(ベ ˇωˇ)べ 摔低低"),
        b("=͟͟͞͞( 'ヮ' 三 'ヮ' =͟͟͞͞)"), b("\\( ﾟ∀。)/"), b("(╬ﾟ∀。)"), b("ᕙ( ﾟ∀。)ᕗ"),
        b("₍˄·͈༝·͈˄₎◞"), b("⁽ ˇᐜˇ⁾"), b("⁽ ˆ꒳ˆ⁾"), b("⁽ ^ᐜ^⁾"),
        b("⁽´°`⁾"), b("⁽´ᵖ`⁾"), b("⁽ ˙³˙⁾"), b("⁽°ᵛ°⁾"),
        b("⁽ `ᵂ´⁾"), b("( ;ˇωˇ; )"), b("(　‸ო‸)"), b("(　‸ω‸)"),
        b("(　^ω。)"), b("/̵͇̿̿/’̿’̿ ̿ ̿̿ ̿̿ ̿̿"), b("( ;´ω`)人 "), b("_(:зゝ∠)_"),
        b("(　ﾟ 灬ﾟ)"), b("( `д´)7"), b("(ᗜᴗᗜ)"), b("(～ﾟωﾟ)～"),
        b("(‸ω‸ ﾐэ)Э"),
        Emoticon(name: "呼伦悲尔", text: "( ﾉд`ﾟ);´д`) ´_ゝ`)", group: .blueIsland),
        Emoticon(name: "鄂尔多厮", text: "Σ( ﾟдﾟ)´ﾟДﾟ)　ﾟдﾟ)))", group: .blueIsland),
        Emoticon(name: "智利", text: "( ﾟ∀。)∀。)∀。)", group: .blueIsland),
        Emoticon(name: "阴山山脉", text: "(　ˇωˇ )◕∀◕｡)^ω^)", group: .blueIsland),
        Emoticon(name: "F5欧拉", text: """
        　σ　σ
        σ(　´ρ`)σ[F5]
        　σ　σ
        """, group: .blueIsland),
        Emoticon(name: "UK酱", text: """
        \\ ︵
        ᐕ)⁾⁾
        """, group: .blueIsland),
        Emoticon(name: "白羊", text: """
        ╭◜◝ ͡ ◜◝ J J
        (　　　　 `д´) 　“咩！”
        ╰◟д ◞ ͜ ◟д◞
        """, group: .blueIsland),
        Emoticon(name: "兔兔", text: """
        　/)　/)
        c(　╹^╹)
        """, group: .blueIsland),
        Emoticon(name: "neko", text: """
        　　　　　∧,,\u{3000}
        　　　　ヾ ｀. ､`フ
        　　　(,｀'´ヽ､､ﾂﾞ
        　 (ヽｖ'　　　`''ﾞつ
        　　,ゝ　 ⌒`ｙ'''´
        　 （ (´＾ヽこつ
        　　 ) )
        　　(ノ
        """, group: .blueIsland),
        Emoticon(name: "给你", text: """
        （\\_/）
        (・_・)
         / 　>
        """, group: .blueIsland),
        Emoticon(name: "举高高", text: """
        　　　　_∧＿∧_\u{20}
        　　 　((∀｀/ 　)\u{20}
        　　　/⌒　　 ／\u{20}
        　　/(__ノ＼_ノ\u{20}
        　　(_ノ ||| 举高高~~
        　∧＿∧　∧＿∧
        (( ・∀・ ))・∀・) )
        `＼　　 ∧ 　　ノ
        　/　｜/　　｜
        （＿ノ＿)_ノL＿)
        """, group: .blueIsland),
        Emoticon(name: "催更喵", text: """
        　　　　　　＿＿＿
        　　　　　／＞　　フ
        　　　　　| 　_　 _ l 我是一只催更的
        　 　　　／` ミ＿xノ 喵喵酱
        　　 　 /　　　 　 | gkdgkd
        　　　 /　 ヽ　　 ﾉ
        　 　 │　　|　|　|
        　／￣|　　 |　|　|
        　| (￣ヽ＿_ヽ_)__)
        　＼二つ
        """, group: .blueIsland),
        Emoticon(name: "巴拉巴拉", text: """
        　∧＿∧
        （｡･ω･｡)つ━☆・*。
        ⊂　　 ノ 　　　・゜+.
        　しーＪ　　　°。+ *´¨)
        　　　 　　.· ´¸.·*´¨) ¸.·*¨)
        　　　　　　　 　(¸.·´ (¸.·’*
        """, group: .blueIsland),
        Emoticon(name: "҉( ﾟ∀。)", text: """
        　　҉
        ( ﾟ∀。)
        """, group: .blueIsland),
        Emoticon(name: "⬭꒰ঌ( ˇωˇ)໒꒱", text: """
        　　⬭
        ꒰ঌ(　ˇωˇ)໒꒱
        """, group: .blueIsland),
        Emoticon(name: "mini阴阳酱", text: "₍˄·͈༝·͈˄₎◞⁽ ˇᐜˇ⁾⁽ ˆ꒳ˆ⁾⁽ ^ᐜ^⁾⁽´°`⁾⁽´ᵖ`⁾⁽ ˙³˙⁾⁽°ᵛ°⁾⁽ `ᵂ´⁾", group: .blueIsland),
        Emoticon(name: "neko2", text: """
        　　　､ゞヾ∧\"\"'∧;,
        　　ヾ　　　・ω・ 彡
        　 ﾐ　　　 　o　 o　 ミ
        　~彡 ﾐ
        　　/ｿ,,　,０; ,;;:､０ヾ`
        """, group: .blueIsland),
        Emoticon(name: "neko3", text: """
        　　　 　／l、\u{20}
        (*´∀`)σ（ﾟ∀。７
         　　　　l、 ~ヽ
        　　　　じしf_, )ノ ​
        """, group: .blueIsland),
        Emoticon(name: "举高高2", text: """
        　　　　_∧＿∧_
        　　　 ((∀｀/ 　)
        　　　 /⌒　　 ／
        　 /(__ノ＼_ノ(((ヽ
        　(_ノ　 　￣Ｙ＼
        |　(＼　(\\　 /)　 ｜ )举高高！
        ヽ　ヽ` ( ﾟ∀ﾟ ) _ノ /
        　＼ |　⌒Ｙ⌒　/ /
        　 ｜ヽ · ｜ · ﾉ ／/
        　 ＼トー仝ーイ
        　　 ｜ ミ土彡/
        　　　). \\ °　 /
        　　　( 　\\. y 　\\
        """, group: .blueIsland),
        Emoticon(name: "举糕糕", text: """
        举糕糕~
        　　☆☆☆☆☆☆☆☆
        　╭┻┻┻┻┻┻┻┻╮
        　┃╱╲╱╲╱╲╱╲┃
        ╭┻━━━━━━━━┻╮
        ┃╱╲╱╲╱╲╱╲╱╲┃
        ┗━━━━━━━━━━┛
        　　　∧＿∧　∧＿∧
        　　(( ・∀・ ))・∀・) )
        　　`＼　　 ∧ 　　ノ
        　　　/　　｜/　　｜
        　　（＿ノ＿)_ノL＿)
        """, group: .blueIsland),
        Emoticon(name: "Happy肥肥Day", text: """
        .　　　　　　　.★ * ★..\u{20}
        　　.*★　*.　*..*　　　★\u{20}
        　　★　　　　　　★\u{20}
        　　‘*. *'　 ʜᴀᴘᴘʏ 肥肥 ᴅᴀʏ\u{20}
        　　　‘★.　　 ★’\u{20}
        　　　　　*..★
        ┊┊┊┊☆☆☆☆☆☆☆☆┊┊┊┊
        ┊┊┊╭┻┻┻┻┻┻┻┻╮┊┊┊
        ┊┊┊┃╱╲╱╲╱╲╱╲┃┊┊┊
        ┊┊╭┻━━━━━━━━┻╮┊┊
        ┊┊┃╱╲╱╲╱╲╱╲╱╲┃┊┊
        ╱▔┗━━━━━━━━━━┛▔╲
        """, group: .blueIsland),
        Emoticon(name: "碣石", text: """
        　　_ _
        　 ( ﾟ_ﾟ)\u{3000}\u{3000}
        /　(⁰　　)╲/
        """, group: .blueIsland),
        Emoticon(name: "冰封王座", text: """
        (ノﾟ∀ﾟ)ノ👑
        　　　( ﾟ∀。)

        　　　👑
        (//ﾟωﾟ)//
        \u{20}\u{20}\u{20}\u{20}
        　👑
        (Ⅱﾟωﾟ)Ⅱ

        　 👑
        ᕕ( ᐛ )ᕗ
        """, group: .blueIsland),
        Emoticon(name: "冰封王座2", text: """
        (ノﾟ∀ﾟ)ノ🍟
        　　　( ﾟ∀。)

        　　　🍟
        (//ﾟωﾟ)//
        \u{20}\u{20}\u{20}\u{20}
        　🍟
        (Ⅱﾟωﾟ)Ⅱ

        　 🍟
        ᕕ( ᐛ )ᕗ
        """, group: .blueIsland),
        Emoticon(name: "冰封王座3", text: """
        ( `д´)=🔪 👑
        　　　 (　ﾟ 3ﾟ)
        　　　👑
        (// `ー´)//
        (　x 3x)
        　👑
        (Ⅱ`∀´)Ⅱ
        (　x 3x)
        　👑
        ( `д´)
        (　x 3x)
        """, group: .blueIsland),
        Emoticon(name: "喵喵酱", text: """
        　^ ^
        ( =`д´=)哈—！
        """, group: .blueIsland),
        Emoticon(name: "狗比酱", text: "(U `д´)<汪汪汪！", group: .blueIsland),
        Emoticon(name: "狼酱", text: """
        　　　　　႔ ႔
        嗷呜！＞ ᠸ`д´ 𐅠
        """, group: .blueIsland),
        Emoticon(name: "起舞", text: """
        ⊂ヽ(　^ω^)つ
        　 ＼ 　　／\u{3000}\u{3000}
        　　( ＿_フ
        　　(／
        """, group: .blueIsland),
        Emoticon(name: "N98", text: """
        淦
        是
        N
        9
        8
        接☆龙☆大☆成☆功
        盗摄？(　^ω^)
        石雕
        要素齐全
        N98是什么？
        同问
        感谢
        谢谢
        要素齐全
        什么是要素齐全？
        淦
        是
        N
        9
        5
        r
        警惕r点机器人
        你一个人都说完了我们说什么(╬ﾟдﾟ)
        """, group: .blueIsland),
        Emoticon(name: "望po石", text: """
        　┏━┓
        　┃望┃
        ᕕ┃po┃ᕗ
        　┃石┃
        　┗━┛
        嗨呀我又来望po了
        我天天都来这望po
        """, group: .blueIsland),
        Emoticon(name: "望po石2", text: """
        　　　　┏━┓
        　　　　┃望┃
        　　　　┃po┃
        　　　　┃石┃
        　　　　┗━┛\u{3000}\u{3000}\u{3000}\u{3000}
        　　　┏━━━┓
        　　┏┛　望　┗┓
        　┏┛　　po　　┗┓
        ┏┛　　　山　　　┗┓
        ┗━━━━━━━━━┛
        """, group: .blueIsland),
        Emoticon(name: "撞墙", text: """
        ┃電柱┃　( ´ー`)
        ┃電柱┃дﾟ ) =͟͟͞͞ =͟͟͞͞
        ┃電柱┃　( ´д`)
        ┃電柱┃дﾟ ) =͟͟͞͞ =͟͟͞͞
        ┃電柱┃　(;´Д`)
        ┃電柱┃π。) =͟͟͞͞ =͟͟͞͞
        """, group: .blueIsland),
        Emoticon(name: "冰箱先生", text: """
        　　/
        ┌───┐
        │　ﾟ∀ﾟ│
        ├─┬─┤
        │　│　│
        └─┴─┘
        """, group: .blueIsland),
        Emoticon(name: "冰箱先生3D", text: """
        　　/
        ▁▁▁▁
        ╲　　　╲
        ▏┌───┐
        ▏│　ﾟ∀ﾟ │
        ▏├─┬─┤
        ╲│　│　│
        　└─┴─┘
        """, group: .blueIsland),
        Emoticon(name: "血压↑", text: """
        　他妈的／＞__フ
        　　　　| ＝ ^ω^)＝　血压↗↗
        　 　　／`　　 丨
        """, group: .blueIsland),
        Emoticon(name: "血压0↓", text: """
        　算逑喽／＞__フ
        　　　　| ＝ ˇωˇ)＝　血压0↓
        　 　　／`　　 丨
        """, group: .blueIsland),
        Emoticon(name: "挺好颜", text: """
        ╯ 　乀
        ヘ　 へ
        　′
        　﹀
        """, group: .blueIsland),
        Emoticon(name: "全角空格", text: "\u{3000}", group: .blueIsland),
        Emoticon(name: "零宽空格", text: "\u{200B}", group: .blueIsland),
    ]

    static let all: [Emoticon] = official + blueIsland

    private static func e(_ text: String) -> Emoticon {
        Emoticon(name: text, text: text, group: .official)
    }

    private static func b(_ text: String) -> Emoticon {
        Emoticon(name: text, text: text, group: .blueIsland)
    }
}
