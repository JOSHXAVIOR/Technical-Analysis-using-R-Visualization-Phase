# Joseph Anil Tenneti | BDA400 Assignment 6
# Step 1: dependencies. Run install_packages.R once before launching.
library(shiny)
library(ggplot2)
library(quantmod)
library(TTR)
library(patchwork)

# Step 4: true crossing events; equality keeps the previous trend direction.
# Missing values produce Hold, and the first valid trend is not a crossing.
cross_signals <- function(delta) {
  out <- rep('Hold', length(delta)); previous <- NA_real_
  for (i in seq_along(delta)) {
    if (!is.finite(delta[i])) { previous <- NA_real_; next }
    current <- sign(delta[i])
    if (current == 0) next
    if (is.finite(previous) && current != previous)
      out[i] <- if (current > 0) 'Buy' else 'Sell'
    previous <- current
  }
  out
}

# Step 2: interactive dashboard skeleton and widgets.
ui <- fluidPage(
  tags$head(tags$style(HTML('body{background:#f3f6fa;color:#17324d} .well{background:white} h2{font-weight:700}'))),
  titlePanel('Portfolio Explorer | Technical Analysis'),
  sidebarLayout(sidebarPanel(
    textInput('ticker', 'Yahoo Finance symbol', 'AAPL'),
    dateRangeInput('dates', 'Visible date range', start=Sys.Date()-365, end=Sys.Date()),
    selectInput('frame', 'Time frame', c('Daily', 'Weekly', 'Monthly')),
    actionButton('fetch', 'Fetch / refresh data', class='btn-primary'),
    selectInput('chart', 'Price chart', c('Candlestick','Line','Area')),
    checkboxGroupInput('indicators', 'Technical indicators',
                       c('Moving Averages','RSI','MACD'), selected=c('Moving Averages','RSI','MACD')),
    numericInput('short', 'Short SMA periods', 20, min=2, max=100),
    numericInput('long', 'Long SMA periods', 50, min=3, max=200),
    numericInput('rsi_n', 'RSI periods', 14, min=2, max=50),
    selectInput('rule', 'Trading rule', c('SMA crossover','MACD crossover','RSI threshold exits')),
    sliderInput('bounds', 'RSI oversold / overbought', min=5, max=95, value=c(30,70)),
    checkboxInput('annotations', 'Show Buy / Sell annotations', TRUE),
    downloadButton('download', 'Download analysis CSV'),
    helpText('Periods follow the selected time frame. Signals are calculated at bar close. Hold means no new crossing.')
  ), mainPanel(
    verbatimTextOutput('summary'), plotOutput('dashboard', height='800px'),
    h4('Latest observations and signals'), tableOutput('recent'),
    tags$p('Price and SMA share the top panel. RSI and MACD use aligned panels with their own units.')
  ))
)

server <- function(input, output, session) {
  # Step 1: explicit refresh, validation, warm-up history and source error handling.
  fetched <- eventReactive(input$fetch, {
    symbol <- toupper(trimws(input$ticker))
    validate(need(grepl('^[A-Z0-9.^=-]+$', symbol), 'Enter a valid Yahoo symbol.'),
             need(length(input$dates)==2 && !anyNA(input$dates), 'Select both dates.'),
             need(input$dates[1] < input$dates[2], 'Start must precede end.'),
             need(input$dates[2] <= Sys.Date(), 'End date cannot be in the future.'))
    # Up to 200 monthly periods require approximately 20 years of warm-up.
    x <- tryCatch(getSymbols(symbol, src='yahoo', from=input$dates[1]-8000,
                            to=input$dates[2]+1, auto.assign=FALSE), error=function(e) NULL)
    validate(need(!is.null(x) && NROW(x)>0,
                  'Yahoo download failed or symbol has no data. Check symbol/network and refresh.'))
    x <- x[!duplicated(index(x))]; x <- x[order(index(x))]
    good <- apply(as.matrix(OHLC(x)), 1, function(v) all(is.finite(v)))
    removed <- sum(!good); x <- x[good]
    validate(need(NROW(x)>0, 'No complete OHLC rows returned.'))
    list(x=x, symbol=symbol, dates=as.Date(input$dates), removed=removed)
  }, ignoreNULL=FALSE)

  analysis <- reactive({
    f <- fetched()
    validate(need(input$short < input$long, 'Short SMA must be smaller than long SMA.'))
    x <- f$x
    # Step 2: OHLC aggregation before indicator computation. Remove incomplete
    # weekly/monthly terminal periods to avoid presenting unfinished crossings.
    if (input$frame=='Weekly') {
      x <- to.weekly(x, indexAt='endof', drop.time=TRUE)
      last <- as.Date(tail(index(x),1))
      if (as.integer(format(last,'%u')) < 5) x <- head(x,-1)
    }
    if (input$frame=='Monthly') {
      x <- to.monthly(x, indexAt='endof', drop.time=TRUE)
      last <- as.Date(tail(index(x),1))
      # If requested end falls before calendar month-end, drop that final month.
      requested_end <- min(f$dates[2], Sys.Date())
      month_end <- as.Date(format(as.Date(format(requested_end,'%Y-%m-01'))+32,'%Y-%m-01'))-1
      if (format(last,'%Y-%m')==format(requested_end,'%Y-%m') && requested_end<month_end)
        x <- head(x,-1)
    }
    validate(need(NROW(x)>max(input$long, input$rsi_n+1, 35), 'Insufficient history for these indicators.'))
    # Step 3: calculate on warm-up history, THEN select the visible dates.
    close <- as.numeric(Cl(x))
    d <- data.frame(Date=as.Date(index(x)), Open=as.numeric(Op(x)),
      High=as.numeric(Hi(x)), Low=as.numeric(Lo(x)), Close=close,
      Volume=as.numeric(Vo(x)))
    d$ShortSMA <- as.numeric(SMA(close,n=input$short))
    d$LongSMA <- as.numeric(SMA(close,n=input$long))
    d$RSI <- as.numeric(RSI(close,n=input$rsi_n))
    m <- MACD(close,nFast=12,nSlow=26,nSig=9,percent=FALSE)
    d$MACD <- as.numeric(m[,1]); d$MACDSignal <- as.numeric(m[,2])
    d$Histogram <- d$MACD-d$MACDSignal
    delta <- switch(input$rule, 'SMA crossover'=d$ShortSMA-d$LongSMA,
                    'MACD crossover'=d$MACD-d$MACDSignal, 'RSI threshold exits'=d$RSI)
    d$Signal <- cross_signals(delta)
    if (input$rule=='RSI threshold exits') {
      prev <- c(NA, head(d$RSI,-1)); d$Signal <- 'Hold'
      buy <- which(is.finite(prev) & is.finite(d$RSI) & prev<=input$bounds[1] & d$RSI>input$bounds[1])
      sell <- which(is.finite(prev) & is.finite(d$RSI) & prev>=input$bounds[2] & d$RSI<input$bounds[2])
      d$Signal[buy] <- 'Buy'; d$Signal[sell] <- 'Sell'
    }
    d <- d[d$Date>=f$dates[1] & d$Date<=f$dates[2],]
    validate(need(nrow(d)>0, 'No completed bars in the selected range.'))
    list(d=d, f=f)
  })

  output$dashboard <- renderPlot({
    a <- analysis(); d <- a$d
    width <- switch(input$frame, Daily=0.65, Weekly=4, Monthly=18)
    common <- theme_minimal(base_size=12)
    p <- ggplot(d,aes(Date)) + labs(title=paste(a$f$symbol,input$frame,input$chart), y='Price (quote currency)',x=NULL) + common
    if (input$chart=='Line') p <- p+geom_line(aes(y=Close),color='#2563eb')
    if (input$chart=='Area') p <- p+geom_area(aes(y=Close),fill='#93c5fd',alpha=.6)+geom_line(aes(y=Close),color='#2563eb')
    if (input$chart=='Candlestick') p <- p+
      geom_linerange(aes(ymin=Low,ymax=High),color='#334155')+
      geom_rect(aes(xmin=Date-width/2,xmax=Date+width/2,ymin=pmin(Open,Close),
                    ymax=pmax(Open,Close),fill=Close>=Open),color='#334155')+
      scale_fill_manual(values=c('TRUE'='#16a34a','FALSE'='#dc2626'),guide='none')
    if ('Moving Averages' %in% input$indicators) p <- p+
      geom_line(aes(y=ShortSMA,color='Short SMA'),na.rm=TRUE)+
      geom_line(aes(y=LongSMA,color='Long SMA'),na.rm=TRUE)
    if (input$annotations) {
      trades <- d[d$Signal!='Hold',]
      p <- p+geom_point(data=trades,aes(y=Close,shape=Signal),size=3,color='#7c3aed')+
        geom_text(data=trades,aes(y=High,label=Signal),vjust=-.5,size=3,color='#7c3aed')
    }
    panels <- list(p)
    if ('RSI' %in% input$indicators) panels <- append(panels,list(
      ggplot(d,aes(Date,RSI))+geom_line(color='#7c3aed',na.rm=TRUE)+
      geom_hline(yintercept=input$bounds,linetype='dashed',color='#64748b')+
      coord_cartesian(ylim=c(0,100))+labs(y='RSI',x=NULL)+common))
    if ('MACD' %in% input$indicators) panels <- append(panels,list(
      ggplot(d,aes(Date))+geom_col(aes(y=Histogram),fill='#94a3b8',width=width,na.rm=TRUE)+
      geom_line(aes(y=MACD,color='MACD'),na.rm=TRUE)+
      geom_line(aes(y=MACDSignal,color='Signal line'),na.rm=TRUE)+
      geom_hline(yintercept=0,linetype='dashed')+labs(y='MACD (price units)',x='Date')+common))
    wrap_plots(panels,ncol=1,heights=c(3,rep(1,length(panels)-1)))
  })
  output$summary <- renderText({
    a <- analysis(); d <- a$d
    paste('Source: Yahoo Finance | Symbol:',a$f$symbol,
      '\nDisplayed:',min(d$Date),'to',max(d$Date),'| Bars:',nrow(d),
      '\nLatest close:',round(tail(d$Close,1),2),'| Latest signal:',tail(d$Signal,1),
      '\nBuy events:',sum(d$Signal=='Buy'),'| Sell events:',sum(d$Signal=='Sell'),
      '\nRule:',input$rule,'| Removed incomplete OHLC rows:',a$f$removed,
      '\nPrices are unadjusted OHLC; no portfolio valuation or strategy backtest is claimed.')
  })
  output$recent <- renderTable({
    d <- tail(analysis()$d,10)
    d[,c('Date','Close','ShortSMA','LongSMA','RSI','MACD','Signal')]
  },digits=2)
  output$download <- downloadHandler(
    filename=function() paste0(analysis()$f$symbol,'_analysis.csv'),
    content=function(file) write.csv(analysis()$d,file,row.names=FALSE))
}
shinyApp(ui, server)
