import Foundation

let sampleCoaches = [
    Coach(
          
            name: "山田コーチ",
            price: 3000,
        area: "所沢",
        imageURL: "",
        availableTimes: [
            ("09:00", true),
            ("10:00", false),
            ("13:00", true),
            ("15:00", false),
            ("17:00", true)
        ],
        ageGroup: "20代",
        careers: [
            "全国大会出場",
            "インカレ ベスト8",
            "JPTA公認プロフェッショナル"
        ],
        tennisExperience: "18年",
        coachingExperience: "6年",
        introduction: "初心者から上級者まで、一人ひとりに合わせたレッスンを行います。"
    ),

    Coach(
       
        name: "佐藤コーチ",
        price: 4000,
        area: "新宿",
        imageURL: "",
        availableTimes: [
            ("09:00", false),
            ("10:00", true),
            ("13:00", true),
            ("15:00", true),
            ("17:00", false)
        ],
        ageGroup: "30代",
        careers: [
            "元インカレ出場",
            "ジュニア全国大会出場",
            "関東学生リーグ優勝"
        ],
        tennisExperience: "20年",
        coachingExperience: "8年",
        introduction: "試合で勝ちたい方を全力でサポートします。"
    ),

    Coach(
       
        name: "鈴木コーチ",
        price: 2500,
        area: "池袋",
        imageURL: "",
        availableTimes: [
            ("09:00", true),
            ("10:00", true),
            ("13:00", false),
            ("15:00", true),
            ("17:00", true)
        ],
        
        ageGroup: "40代",
        careers: [
            "実業団日本リーグ出場",
            "全国選抜出場",
            "ジュニア育成実績多数"
        ],
      
    
        tennisExperience: "25年",
        coachingExperience: "12年",
      
        introduction: "初心者からジュニアまで楽しく上達できるレッスンを心掛けています。"
    )
]
