# 测试数据加载
cat("开始测试数据加载...\n")

# 检查文件存在
if (file.exists("data/liaochu.RData")) {
  cat("data/liaochu.RData 文件存在\n")
  
  # 尝试加载
  tryCatch({
    load("data/liaochu.RData")
    cat("数据加载成功\n")
    
    # 检查对象
    objects <- ls()
    cat("加载的对象:", paste(objects, collapse=", "), "\n")
    
    # 检查liaochu对象
    if (exists("liaochu")) {
      cat("liaochu对象存在，类型:", class(liaochu), "\n")
      cat("包含标的数量:", length(liaochu), "\n")
      
      # 查找PEPE相关标的
      all_names <- names(liaochu)
      pepe_names <- all_names[grepl("PEPE", all_names, ignore.case=TRUE)]
      cat("PEPE相关标的:", paste(pepe_names, collapse=", "), "\n")
      
      if (length(pepe_names) > 0) {
        # 检查第一个PEPE数据的结构
        first_pepe <- liaochu[[pepe_names[1]]]
        cat("第一个PEPE数据结构:\n")
        cat("- 类型:", class(first_pepe), "\n")
        cat("- 行数:", nrow(first_pepe), "\n")
        cat("- 列名:", paste(names(first_pepe), collapse=", "), "\n")
        
        # 显示前几行
        cat("前3行数据:\n")
        print(head(first_pepe, 3))
      }
    } else {
      cat("liaochu对象不存在\n")
    }
    
  }, error = function(e) {
    cat("加载失败，错误:", e$message, "\n")
  })
  
} else {
  cat("data/liaochu.RData 文件不存在\n")
}

cat("测试完成\n")
