# dashboard.py — Streamlit Betting Dashboard

import streamlit as st
import pandas as pd
import pymysql
import sqlalchemy
from sqlalchemy import create_engine
import os

# MySQL config
MYSQL_CONFIG = {
    'host': os.getenv('DB_HOST', '35.246.3.197'),
    'user': os.getenv('DB_USER', 'nordicuser'),
    'password': os.getenv('DB_PASSWORD', 'NordicPass123!'),
    'database': os.getenv('DB_NAME', 'BettingModel')
}

engine = create_engine(
    f"mysql+pymysql://{MYSQL_CONFIG['user']}:{MYSQL_CONFIG['password']}@{MYSQL_CONFIG['host']}/{MYSQL_CONFIG['database']}"
)

st.set_page_config(page_title="Nordic Value Bets", layout="wide")
st.title("📊 Nordic Value Betting Dashboard")

# Tabs
tab1, tab2, tab3 = st.tabs(["💡 Single Market", "🎯 Combo Bets", "📈 Evaluation Reports"])

with tab1:
    market = st.selectbox("Select Market", ["pred_result", "pred_btts", "pred_over_2_5"])
    df = pd.read_sql(f"SELECT * FROM {market}", engine)
    df = df.sort_values("match_date")

    min_conf = st.slider("Minimum confidence (probability)", 0.0, 1.0, 0.7, 0.01)
    date_filter = st.date_input("Filter by match date", pd.to_datetime("today").date())

    filtered = df[(df['match_date'] >= pd.to_datetime(date_filter)) & (df.filter(like='prob_').max(axis=1) >= min_conf)]
    st.write(f"### Showing {len(filtered)} bets")
    st.dataframe(filtered, use_container_width=True)

with tab2:
    combo = pd.read_sql("SELECT * FROM combo_value_bets", engine)
    combo = combo.sort_values("match_date_result")
    st.write("### Combo Bets (e.g. Result + BTTS)")
    combo_filter = combo[combo['confidence'] >= st.slider("Min combo confidence", 0.0, 1.0, 0.7, 0.01)]
    st.dataframe(combo_filter, use_container_width=True)

with tab3:
    for table in ["eval_result", "eval_btts", "eval_over_2_5"]:
        st.write(f"### {table}")
        eval_df = pd.read_sql(f"SELECT * FROM {table}", engine)
        st.dataframe(eval_df, use_container_width=True)

st.caption("© 2025 Nordic Model - Streamlit Dashboard")
