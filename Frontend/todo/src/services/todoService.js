import axios from 'axios';

// Uses /api in Docker and supports a custom URL for local development.
const API_BASE_URL = process.env.REACT_APP_API_BASE_URL || '/api';
const TODOS_URL = `${API_BASE_URL.replace(/\/$/, '')}/todos`;

const todoService = {
  getAllTodos: () => axios.get(TODOS_URL),
  createTodo: (todo) => axios.post(TODOS_URL, todo),
  updateTodo: (id, todo) => axios.put(`${TODOS_URL}/${id}`, todo),
  deleteTodo: (id) => axios.delete(`${TODOS_URL}/${id}`),
  summarizeTodos: () => axios.post(`${TODOS_URL}/summarize`),
};

export default todoService;