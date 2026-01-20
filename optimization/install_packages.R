if (!require('ParBayesianOptimization', quietly = TRUE)) {
  cat('Installing ParBayesianOptimization...\n')
  install.packages('ParBayesianOptimization', repos='https://cloud.r-project.org')
  cat('ParBayesianOptimization installed successfully!\n')
} else {
  cat('ParBayesianOptimization is already installed.\n')
}
