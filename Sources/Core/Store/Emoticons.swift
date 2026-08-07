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
        Emoticon(name: "呼伦悲尔", text: "( ﾉд`ﾟ);´д`) ´_ゝ`) ", group: .blueIsland),
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
        　　       　∧,,
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
        　　　　_∧＿∧_
        　 ((∀｀/ 　)
        　/⌒　　 /
        /(__ﾉ＼_ノ
        　 (_ノ
        """, group: .blueIsland),
        Emoticon(name: "催更喵", text: """
        　　　　　　＿＿＿
        　　　　　／＞　　フ
        　　　　　|  　_　 _ l 我是一只催更的
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
    ]

    static let all: [Emoticon] = official + blueIsland

    private static func e(_ text: String) -> Emoticon {
        Emoticon(name: text, text: text, group: .official)
    }

    private static func b(_ text: String) -> Emoticon {
        Emoticon(name: text, text: text, group: .blueIsland)
    }
}
